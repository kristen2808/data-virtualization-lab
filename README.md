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
