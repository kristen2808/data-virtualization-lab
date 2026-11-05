# Local Trino PoC

## Quick reference

- Trino: `https://localhost:8443` with PASSWORD authentication.
- PostgreSQL: `localhost:5433`, database `lab_db`; credentials in `.env`.
- SQL Server 2022 Developer: `localhost:1433`, login `sa`; password in `.env`.
- `admin`: full configured administrative access across all catalogs.
- `analyst`: SELECT on `pg_lab.public` and `mssql_lab.dbo`, JDBC metadata, and own query management.
- Start: `docker compose up -d`; stop: `docker compose down` (keeps data).
- Verify permissions: `python3 scripts/verify_access_control.py` (interactive).
- Keep `.env` and `secrets/` out of Git. Setup instructions follow below.

Requirements: a running Docker Engine and Docker Compose v2.

The `trino` service uses the official `trinodb/trino:484` image and a container
named `trino`. The default image configuration runs both the coordinator
and worker in a single container. HTTPS port 8443 is available only on
localhost. Internal HTTP port 8080 is not published.
`trino/config.properties` preserves discovery and catalog defaults and enables
HTTPS with PASSWORD authentication and file-based system access control.
`admin` has the broadest configured administrative permissions; `analyst`
can only SELECT from `pg_lab.public` and `mssql_lab.dbo`, read JDBC metadata,
and manage own queries.

The `postgres` service uses a container named `trino-postgre`, the official
`postgres:17.11-bookworm` image, the `lab_db` database, and the named
`postgres_data` volume. PostgreSQL is accessible from the host at
`127.0.0.1:5433`; credentials are stored in the local `.env` file.
Trino connects over the internal network to `postgres:5432` through the
`pg_lab` catalog. Its configuration in `trino/catalog/pg_lab.properties`
is mounted read-only. Trino starts after PostgreSQL passes its healthcheck.

## Start the services

From the project root:

```sh
cp .env.example .env
```

In your local `.env`, replace the example password with your own password
and optionally change the username. Git ignores this file; never commit it.
For passwords containing `$` or `#`, use single quotes in `.env` to preserve
the literal value. Do not put real passwords in other project files.

Before the first start, generate a local self-signed certificate with OpenSSL
supporting `-addext`. Do not repeat this step unless you intend to replace the
certificate (valid for 365 days):

```sh
mkdir -p secrets/trino
chmod 700 secrets secrets/trino
(
  umask 077
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out secrets/trino/localhost.key
  openssl req -new -x509 -sha256 -days 365 \
    -key secrets/trino/localhost.key -out secrets/trino/localhost.crt \
    -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
    -addext 'extendedKeyUsage=serverAuth'
  cat secrets/trino/localhost.key secrets/trino/localhost.crt \
    > secrets/trino/localhost.pem
)
chmod 644 secrets/trino/localhost.pem secrets/trino/localhost.crt
```

Git ignores `secrets/`. The directories have mode `700`, protecting the key
and combined PEM from other host users. The PEM has mode `644` so the
container's Trino user (UID 1000) can read the individual read-only bind mount;
the containing host directories remain private. The separate key has mode `600`.
Never commit or share the combined PEM or private key.

## Configure password authentication

The file authenticator is configured in `trino/password-authenticator.properties`.
Its password database and internal shared secret are stored only in ignored
`secrets/trino/` files. For a new checkout, create them without overwriting any
existing files:

```sh
python3 - <<'PYSETUP'
import os
import secrets
from pathlib import Path
root = Path('secrets/trino')
root.mkdir(parents=True, exist_ok=True)
Path('secrets').chmod(0o700)
root.chmod(0o700)
for name in ('internal.env', 'password.db'):
    try:
        fd = os.open(root / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        continue
    with os.fdopen(fd, 'w') as f:
        if name == 'internal.env':
            f.write('TRINO_INTERNAL_SHARED_SECRET=' + secrets.token_hex(64) + '\n')
PYSETUP
```

Check that `htpasswd` supports bcrypt (`-B`) and cost (`-C`). On macOS it is
normally available at `/usr/sbin/htpasswd`. If unavailable, install Apache's
`htpasswd` utility from a trusted package source before continuing.

Enter distinct passwords interactively; do not put passwords in command arguments
or chat. These commands add users to the initially empty database, or update
only the named user in an existing database. Confirm an intended password change
before running them against an existing account. Do not use `-b` or `-c`.
Use a password manager; keep bcrypt passwords within 72 bytes.

```sh
htpasswd -B -C 12 secrets/trino/password.db admin
htpasswd -B -C 12 secrets/trino/password.db analyst
chmod 644 secrets/trino/password.db
```

The password database contains bcrypt hashes and is mounted read-only. Mode
`644` permits the container's UID 1000 to read the individual bind mount;
the host directories remain private (`700`). `internal.env` remains `600`.
Anyone with Docker administrative access can access container secrets.
Never print expanded Compose configuration, container environment, or these files.
The shared secret authenticates internal node communication; it is not a user
password. Do not change it unnecessarily.

Validate the configuration without printing its values, then start the services:

```sh
docker compose config --quiet
docker compose up -d
```

After changing the Compose configuration, run `docker compose up -d` again.
Compose recreates containers as needed, for example after changing a container
name or port mapping. Use the service name `postgres` in `docker compose`
commands and the container name `trino-postgre` in `docker` commands.

## Verify the setup and open the web UI

```sh
docker compose config --quiet
docker compose ps
docker compose logs trino
```

Wait until the Trino container is `healthy` (`SERVER STARTED` appears in its
logs). Open the web UI at <https://localhost:8443>.
Browsers do not trust the self-signed certificate automatically.
HTTP is available only inside Docker for discovery and healthchecks.
User authentication over HTTP is explicitly disabled.

Verify HTTPS while checking both certificate trust and the hostname:

```sh
curl --fail --show-error --cacert secrets/trino/localhost.crt \
  https://localhost:8443/v1/info
```

The response should report version `484` and `starting: false`.
The `/v1/info` endpoint is public and does not test password authentication.
The web UI now requires the configured username and password.

The CLI accepts the public certificate as a PEM truststore. With a local CLI:

```sh
trino --server https://localhost:8443 \
  --truststore-path secrets/trino/localhost.crt --user admin --password
```

Alternatively, use the CLI included in the container. The public certificate is
mounted read-only and remains available after container recreation:

```sh
docker compose exec trino trino --server https://localhost:8443 \
  --truststore-path /etc/trino/tls/localhost.crt --user admin --password
```

For an existing setup, run `chmod 644 secrets/trino/localhost.crt` once so the
container's Trino user can read the public certificate. No certificate copy or
root command inside the container is needed.

Repeat for `analyst`. The password prompt is interactive; do not set or print
`TRINO_PASSWORD` or place passwords in command arguments.
For each user, run:

```sql
SELECT current_user;
SHOW CATALOGS;
SHOW SCHEMAS FROM pg_lab;
SHOW TABLES FROM pg_lab.public;
```

Expect the matching username, catalog `pg_lab`, and schema `public`.
These checks do not create tables or data. Both users still use the same
PostgreSQL connector credentials; Trino applies user authorization before access.

Test the SQL endpoint with curl; `--user admin` prompts for the password:

```sh
curl --cacert secrets/trino/localhost.crt --user admin \
  -H 'X-Trino-User: admin' --data-binary 'SELECT current_user' \
  https://localhost:8443/v1/statement
```

Repeat for `analyst`. Follow any returned `nextUri` using the same TLS validation
and credentials to retrieve results. A wrong password or omitted credentials
must return HTTP 401. Do not use verbose curl output when sending credentials.
Test missing credentials without printing response bodies:

```sh
curl --cacert secrets/trino/localhost.crt -sS -o /dev/null \
  -w '%{http_code}\n' -H 'X-Trino-User: admin' \
  --data-binary 'SELECT 1' https://localhost:8443/v1/statement
```

Ensure host port 8080 is absent from `docker compose ps`. Verify internal HTTP
rejects SQL even with a forged username (expect HTTP 401 or 403):

```sh
docker compose exec -T trino curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'X-Trino-User: admin' --data-binary 'SELECT 1' \
  http://localhost:8080/v1/statement
```

The image healthcheck still uses public HTTP `/v1/info`, so it needs no user
password. Internal discovery continues to use `http://localhost:8080`.

In DBeaver, use the Trino driver, `localhost:8443`, `SSL=true`,
`SSLVerification=FULL`, and `SSLTrustStorePath` pointing to the absolute path of
`secrets/trino/localhost.crt` (the public PEM certificate).
Enter each Trino user's password through the login dialog, not the JDBC URL.
Verify both logins, rejection of a wrong password, and the SQL checks above.
Do not disable TLS certificate validation for the self-signed certificate.
PostgreSQL remains separately accessible on localhost:5433 with its own credentials.

## File-based system access control

`trino/access-control.properties` loads `trino/access-control/rules.json`.
Both paths are mounted read-only. Rules are evaluated first-match within each
section. Explicit rule lists deny unmatched operations; omitting a section can
have permissive defaults. Restart Trino after changing rules.

- `admin` has catalog `owner` access to all current and future catalogs, schema
  ownership, all table privileges, function and procedure privileges, all session
  properties, query execution/view/cancellation, system information read/write,
  and ownership reassignment. System write access includes graceful shutdown.
- `analyst` has read-only catalog access to `pg_lab`, `mssql_lab`, and `system`,
  SELECT on `pg_lab.public`, `mssql_lab.dbo`, and `system.jdbc`, and management
  of own queries only.
  PostgreSQL passthrough functions/procedures and other catalogs are denied.
- Impersonation is denied for both users. PASSWORD authentication is unchanged.
- Built-in functions and filtered `information_schema` metadata have special
  handling. DBeaver DDL previews or session-setting features may be denied to
  `analyst`; do not broaden permissions without reviewing the exact failure.
- File-based access control does not support role administration and does not
  independently restrict table procedures (`ALTER TABLE ... EXECUTE`). Review
  connector capabilities before adding catalogs. Static catalog management
  remains enabled, so SQL catalog creation is still unavailable.
- Backend account permissions and connector capabilities still limit `admin`.
  Direct PostgreSQL connections bypass Trino authorization. Do not share the
  technical PostgreSQL credentials with analysts.
- Configuration, credentials, and infrastructure are administered through files,
  Docker, and Git, not SQL. Secrets must never be committed.

Validate without exposing environment values:

```sh
python3 -m json.tool trino/access-control/rules.json > /dev/null
docker compose config --quiet
docker compose up -d --no-deps trino
```

Run the interactive integration checks from the host with Python 3:

```sh
python3 scripts/verify_access_control.py
```

The script prompts for both passwords without echoing them, validates TLS against
`secrets/trino/localhost.crt`, and keeps credentials only in memory. It tests
catalog visibility, metadata, SELECT, passthrough rejection, and query ownership
via REST. Query cancellation checks use completed probe queries to verify endpoint
authorization without cancelling any application workload.

DDL/DML tests create uniquely named `pg_lab.public.acl_probe_<uuid>` tables only.
They check admin CREATE/INSERT/UPDATE/DELETE/DROP and analyst rejection of those
operations. Cleanup runs in `finally`; if the process is forcibly killed or the
server becomes unreachable, remove only the exact reported probe table names as
admin after reviewing the failure. Never clean up unrelated tables or volumes.
A failure does not change permissions. Share only the PASS/FAIL report, not
passwords or secrets. These tests require interactive execution and are not
considered passed until the report completes successfully.

Reference: [Trino 484 file-based access control](https://trino.io/docs/current/security/file-system-access-control.html).

## SQL Server catalog in Trino

`trino/catalog/mssql_lab.properties` defines the `mssql_lab` SQL Server connector
and is mounted read-only. It connects to `sqlserver:1433`, database `lab_mssql`,
over the internal Compose network. The source tables must already exist.

Trino receives `MSSQL_USER` (default `sa`) and `MSSQL_SA_PASSWORD` from the local
Compose environment / ignored `.env`. Add `MSSQL_USER=sa` to `.env` if desired;
reuse the existing SQL Server password without printing it or changing it.
`.env.example` documents the variable names only. No credentials are stored in
the catalog file. Docker administrators can inspect container environment values.

Using `sa` gives the connector broad backend privileges for this local PoC.
Replace it with a dedicated technical account with minimum database permissions
in a later task; then separate its password variable from the server's SA password.
Trino's `admin` policy already covers all catalogs. `analyst` can SELECT only from
`mssql_lab.dbo` (plus existing PostgreSQL data and JDBC metadata); writes, DDL,
SQL Server passthrough functions/procedures, and impersonation remain denied.

The JDBC URL uses `encrypt=true;trustServerCertificate=true`: traffic is encrypted,
but the SQL Server certificate is **not validated**. Use this only for the local
PoC. For deployment, configure a trusted server certificate, validate its hostname,
and set `trustServerCertificate=false`. Trino client HTTPS settings are unchanged.

The catalog and environment changes require recreating Trino in a later,
explicitly approved verification step; they are not hot-loaded by static catalog
management. No container restart or SQL test is performed merely by editing files.
Once applied, use DBeaver's existing Trino HTTPS connection or a local CLI:

```sh
trino --server https://localhost:8443 \
  --truststore-path secrets/trino/localhost.crt --user analyst --password
```

Enter the password interactively. Run these read-only checks as both `admin`
and `analyst`:

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM mssql_lab;
SHOW TABLES FROM mssql_lab.dbo;
SELECT count(*) FROM mssql_lab.dbo.orders;
SELECT count(*) FROM mssql_lab.dbo.order_items;
SELECT order_id, customer_id, order_date, status
FROM mssql_lab.dbo.orders
ORDER BY order_id
LIMIT 10;
```

The deterministic fixture has 10000 orders and 30000 order items. These counts
apply only after the source seed scripts have successfully completed.

Reference: [Trino SQL Server connector](https://trino.io/docs/current/connector/sqlserver.html).

## SQL Server 2022 on Apple Silicon

The `sqlserver` service uses the official
`mcr.microsoft.com/mssql/server:2022-latest` image with `platform: linux/amd64`,
`ACCEPT_EULA=Y`, and `MSSQL_PID=Developer` (development/testing only).
The requested `2022-latest` tag is mutable within the 2022 release line.
Data persists in the `sqlserver_data` volume mounted at `/var/opt/mssql`.
The host endpoint is `127.0.0.1:1433`; other Compose containers use
`sqlserver:1433` on the existing default network. The Trino catalog is configured
separately as described above; the service
configuration does not create application databases or tables.

Add `MSSQL_SA_PASSWORD` to your existing local `.env`; do not replace that file
or overwrite existing PostgreSQL credentials. For a fresh checkout, use
`.env.example` as described above. Set a unique password from a password manager,
preferably at least 16 characters and including uppercase, lowercase, digits,
and symbols. Use single quotes around the value to preserve `$` and `#` literally.
The example deliberately leaves the value empty, and Compose rejects an empty
or missing value. Keep `.env` private (`chmod 600 .env`) and never commit it.
Git already ignores `.env`, `.env.*` (except `.env.example`), and `secrets/`.
Docker administrators can read container environment variables; do not print
expanded Compose configuration or container environment.

Start only SQL Server, leaving the other services running unchanged:

```sh
docker compose config --quiet
docker compose up -d --no-deps sqlserver
docker compose ps sqlserver
docker compose logs --tail 100 sqlserver
```

Wait for `SQL Server is now ready for client connections` in the logs.
A running container alone does not mean SQL Server is ready. Verify a SQL
connection using the image's sqlcmd utility; omitting `-P` prompts for the password:

```sh
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -C -Q 'SELECT @@VERSION;'
```

`-C` trusts SQL Server's local server certificate for this PoC; it does not change
Trino's TLS configuration. This check reads server metadata only. To stop just
this service, use `docker compose stop sqlserver`. Do not use `down -v` if you
want to preserve database data. Changing the environment password is not a
password rotation procedure for an already initialized persistent instance.

SQL Server's Linux image targets x86-64, not ARM64. On an M1 Pro, Docker must
emulate AMD64; `platform` selects the architecture but does not guarantee that
SQL Server will start. Microsoft does not test or support Rosetta/QEMU execution.
Expect slower startup, higher resource usage, or crashes. Ensure Docker Desktop
has AMD64 emulation available and sufficient memory (SQL Server alone requires
at least 2 GB). If emulation fails, use an x86-64 Linux host for SQL Server;
keep the existing Trino/PostgreSQL services unchanged.

References: [Microsoft container deployment and platform support](https://learn.microsoft.com/en-us/sql/linux/containers/deploy?view=sql-server-ver16)
and [SQL Server container quickstart](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker).

## One-off REST API ingestion with dlt

Core services (Trino, PostgreSQL, and SQL Server) are defined in `compose.yaml`.
The optional one-off `dlt` service is defined in `compose.dlt.yaml`; always pass
both files, with `compose.yaml` first, when building or running the pipeline.
All services share the existing project network and persistent database volumes.

The `dlt` service loads `https://jsonplaceholder.typicode.com/users` into
`lab_db.api_data.users` using Python 3.12 and `dlt[postgres]==1.32.0`.
`pipelines/api_users.py` uses dlt's declarative REST API source and a single-page
paginator. There are no custom HTTP requests. Nested address/company fields
are normalized by dlt into columns.

Use the existing `POSTGRES_USER` and `POSTGRES_PASSWORD` in the ignored `.env`.
Compose passes them as `DESTINATION__POSTGRES__CREDENTIALS__USERNAME` and
`DESTINATION__POSTGRES__CREDENTIALS__PASSWORD`, together with host `postgres`,
port `5432`, and database `lab_db`. No new credentials or network are needed.
The database user must be allowed to create schemas/tables and merge rows.

From the project root:

```sh
docker compose -f compose.yaml -f compose.dlt.yaml build dlt
docker compose -f compose.yaml -f compose.dlt.yaml run --rm dlt
```

The overlay preserves the `pipelines` profile, which prevents the one-off job
from running even when both files are supplied to a general `up` command.
The default Compose file contains only the core services for ordinary
`docker compose up -d`. Explicitly targeting `dlt` with `run` enables the service;
its dependency starts PostgreSQL if needed and waits for the existing healthcheck.
The container exits after loading and is removed by `--rm`. Existing Trino,
PostgreSQL, and SQL Server service definitions are unchanged.

Each run fetches all users and uses `merge` with primary key `id`. A second run
updates matching users rather than appending duplicates. Run jobs sequentially,
not concurrently. This is an upsert, not a full snapshot deletion: users absent
from a later API response are not automatically removed. Use `api_data.users`
only for this pipeline; do not point it at unrelated application data.

The first run creates the `api_data` schema, a staging schema `api_data_staging`,
and dlt metadata tables. Local pipeline state is temporary in the container;
dlt restores its state/schema from PostgreSQL on later runs. There is no new
Docker volume and no cleanup of existing database data. Build context is limited
by `docker/dlt/Dockerfile.dockerignore`, excluding `.env` and `secrets/`.

Verify through the direct PostgreSQL connection in DBeaver (`lab_db`):

```sql
SELECT count(*) AS users_count, count(DISTINCT id) AS distinct_users
FROM api_data.users;
SELECT id, count(*) FROM api_data.users GROUP BY id HAVING count(*) > 1;
SELECT id, name, username, email FROM api_data.users ORDER BY id;
```

Run the job twice and repeat the checks. JSONPlaceholder normally supplies 10
users: expect both counts to be 10 and the duplicate query to return no rows.
Trino's existing `admin` can query `pg_lab.api_data.users`; `analyst` remains
restricted to its existing schemas and is not granted access to `api_data` here.
No Trino configuration changes are needed.

References: [dlt REST API source](https://dlthub.com/docs/dlt-ecosystem/verified-sources/rest_api/basic)
and [PostgreSQL destination](https://dlthub.com/docs/dlt-ecosystem/destinations/postgres).

## Superset metadata database

`scripts/postgres/03_superset_metadata.sql` prepares a separate database
`superset_metadata` owned by login role `superset`. The role has no SUPERUSER,
CREATEDB, CREATEROLE, REPLICATION, or BYPASSRLS privileges. It does not use the
analytical `lab_db` database for Superset metadata. No Superset service, migrations,
or administrator account are installed by this step.

This is a **psql script**, using `\if`, `\gexec`, and password handling; do not
execute it as ordinary SQL in DBeaver. PostgreSQL's volume is already initialized,
so `/docker-entrypoint-initdb.d/` is not used. Run manually against maintenance
database `postgres` as `lab_user`, outside any transaction (`psql -1` is invalid):

```sh
docker cp scripts/postgres/03_superset_metadata.sql trino-postgre:/tmp/03_superset_metadata.sql
docker compose exec postgres sh -c \
  'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -f /tmp/03_superset_metadata.sql'
```

For a new role, psql prompts twice for its password without echoing it and sends
an encrypted SCRAM verifier to PostgreSQL. Store that password in a password
manager. For an existing role, there is no prompt and the password is preserved.
The script refuses incompatible existing role privileges, role memberships,
or database ownership/settings rather than silently changing them.

For automated initialization, the optional `SUPERSET_DB_PASSWORD` environment
variable accepts either the new password or a PostgreSQL SCRAM verifier. Pass
only the environment variable's name through Docker, not its value on the command
line. Do not enable SQL tracing or verbose logging; plaintext environment values
are visible to administrators, and a plaintext SQL password assignment may be
recorded by server auditing. Prefer the interactive `\password` method or an
already generated SCRAM verifier. Never commit a password or verifier.

Initialization in this lab has been tested successfully. A generated password
is stored only in ignored `secrets/superset/metadata.env` (file mode `600`, parent
directories `700`). Preserve it for the later Superset integration; do not replace
it during a rerun. It is not added to Compose or baked into any image.
If this local credentials file is present, a non-interactive rerun is:

```sh
(
  set -a
  . ./secrets/superset/metadata.env
  set +a
  docker compose exec -T -e SUPERSET_DB_PASSWORD postgres sh -c \
    'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -f -' \
    < scripts/postgres/03_superset_metadata.sql
)
```

The existing role's password is ignored on reruns, even if an environment value
is supplied. Password rotation is a separate explicit operation; use an admin
psql session and `\password superset` when intentionally rotating it, then update
the local secret used by Superset.

Verify as `lab_user` using DBeaver or psql:

```sql
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
       rolreplication, rolbypassrls
FROM pg_roles WHERE rolname = 'superset';

SELECT datname, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname = 'superset_metadata';
```

Expect LOGIN true, all listed administrative attributes false, and database
owner `superset`. Test password authentication separately (enter the saved
password when prompted):

```sh
docker compose exec postgres psql -X -h 127.0.0.1 -U superset \
  -d superset_metadata -W -c 'SELECT current_database(), current_user;'
```

Role creation and password setup are transactional. `CREATE DATABASE` must run
in auto-commit mode, so initialization cannot be one atomic transaction; if it
fails after role creation, fix the cause and rerun. Session advisory locking
serializes this script. Existing databases and their contents are never dropped,
reinitialized, or migrated. This does not change cluster-wide PUBLIC privileges;
the role is not a full isolation boundary from every other database.

## Superset web application

`compose.superset.yaml` adds `superset` and the one-off `superset-init` service.
Both use our custom image based on **`apache/superset:6.0.0`**, with
`psycopg2-binary==2.9.11`, `trino[sqlalchemy]==0.340.0`, and SQLAlchemy 1.4.54.
The application connects as database role `superset` to
`postgres:5432/superset_metadata`. `SUPERSET_DB_PASSWORD` is read from the
existing `secrets/superset/metadata.env`. It never uses SQLite or `lab_db`
for its metadata.

Initialize the metadata database as described above before starting the app.
Create application secrets without overwriting any existing values:

```sh
python3 scripts/setup_superset_secrets.py
```

The helper creates these ignored files with mode `600` under private directories:

| File | Purpose |
|---|---|
| `secrets/superset/metadata.env` | Existing PostgreSQL `SUPERSET_DB_PASSWORD`; unchanged |
| `secrets/superset/application.env` | Persistent random `SUPERSET_SECRET_KEY`, shared by init and web |
| `secrets/superset/admin.env` | Initial web admin username, password, name, and email; init only |

The default web username is `admin`. Retrieve its generated password privately
from `admin.env` in a local editor; do not paste it into chat or commit it.
You may edit initial account details before the first initialization. Existing
users are never overwritten, promoted, or assigned a new password on reruns.
An existing inactive/non-Admin account with the same name causes an error.
These credentials are separate from PostgreSQL and Trino accounts.

From the project root:

```sh
docker compose -f compose.yaml -f compose.superset.yaml config --quiet
docker compose -f compose.yaml -f compose.superset.yaml build superset
docker compose -f compose.yaml -f compose.superset.yaml up -d superset
docker compose -f compose.yaml -f compose.superset.yaml ps -a superset superset-init
curl --fail http://localhost:8088/health
```

`superset-init` waits for PostgreSQL, runs `superset db upgrade` and `superset init`,
then creates a missing administrator through Superset's security manager.
The web service starts only after init exits successfully. Init may run again
when starting the application; reruns preserve the administrator password.
To rerun initialization explicitly:

```sh
docker compose -f compose.yaml -f compose.superset.yaml run --rm superset-init
```

Open <http://localhost:8088> and log in with the credentials in `admin.env`.
The service binds only to `127.0.0.1:8088`. It uses one Gunicorn process with
threads and local in-memory caches. Queries run synchronously: no Celery worker,
Redis, scheduled reports, or global async queries are configured. Leave
**Asynchronous query execution** disabled when adding analytical databases.
Drivers are installed, but analytical database connections are not created
automatically. Trino still requires its existing HTTPS/password credentials and
appropriate TLS trust configuration in a later connection setup step.

Verify metadata in a direct PostgreSQL connection to `superset_metadata`:

```sql
SELECT current_database(), current_user;
SELECT version_num FROM public.alembic_version;
SELECT username, active FROM public.ab_user;
SELECT count(*) AS metadata_tables
FROM information_schema.tables
WHERE table_schema='public' AND table_type='BASE TABLE';
```

Expect database `superset_metadata`, an Alembic revision, and the admin user.
Dashboards, users, and saved connections persist in the existing PostgreSQL
volume. Keep `application.env` backed up alongside database backups: changing
`SUPERSET_SECRET_KEY` arbitrarily breaks encrypted credentials and sessions.
No new volume is introduced. Superset migrations modify only its dedicated
metadata database. For future version upgrades, back it up before migration.

Stop only Superset services without removing PostgreSQL data:

```sh
docker compose -f compose.yaml -f compose.superset.yaml stop superset superset-init
```

This is a local HTTP PoC, not a hardened deployment. CSRF remains enabled;
TLS/security response-header enforcement is disabled for the local HTTP endpoint.
Do not expose port 8088 externally without configuring deployment security.
Never print the expanded Compose configuration, container environment, passwords,
or secret key.

References: [Superset Docker images](https://superset.apache.org/admin-docs/installation/docker-builds/)
and [Superset configuration](https://superset.apache.org/admin-docs/configuration/configuring-superset/).

## Stop and remove the containers

```sh
docker compose down
```

PostgreSQL data remains in the named volume. Avoid `down -v` if you want to
keep it. PostgreSQL initialization variables apply only on the first start
with an empty volume. Changing `.env` alone does not change the password
or user in an existing database.

References: [official Trino Docker image documentation](https://trino.io/docs/current/installation/containers.html)
and [default configuration for version 484](https://github.com/trinodb/trino/blob/484/core/docker/default/etc/config.properties).
See also the [PostgreSQL connector](https://trino.io/docs/current/connector/postgresql.html)
and [official PostgreSQL image](https://hub.docker.com/_/postgres).
