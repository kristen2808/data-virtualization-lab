# Trino setup and access

[Project overview](../README.md) · [Docker](../docker/README.md) · [SQL scripts](../scripts/README.md)

Trino 484 runs as coordinator and worker in one container.
HTTPS uses port 8443. PASSWORD login and file-based access control are enabled.
HTTP port 8080 stays inside Docker for discovery and healthchecks.

## Configuration files

| File | Purpose |
|---|---|
| [config.properties](config.properties) | Single-node settings, HTTPS, and authentication |
| [password-authenticator.properties](password-authenticator.properties) | Local bcrypt password file |
| [access-control.properties](access-control.properties) | Load the access rules |
| [rules.json](access-control/rules.json) | User permissions |
| [catalog/](catalog/) | Source connections |
| [OpenAPI spec](openapi/jsonplaceholder.yaml) | Public GET endpoints |

Compose mounts these files read-only. TLS files and passwords stay in ignored
`secrets/trino/`. Keep discovery, catalog management, and cache settings when
editing `config.properties`. The image supplies `CATALOG_MANAGEMENT`.

## First setup

Run commands from the project root. First create your local `.env` with the
[Docker setup guide](../docker/README.md#first-setup). Keep existing secrets.

Before the first start, generate a local self-signed certificate with OpenSSL
supporting `-addext`. Do not repeat this step unless you intend to replace the
certificate (valid for 365 days):

```sh
mkdir -p secrets/trino
chmod 700 secrets secrets/trino
(
  umask 077
  if [ ! -f secrets/trino/localhost.key ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
      -out secrets/trino/localhost.key
  fi
  if [ -e secrets/trino/localhost.crt ] || [ -e secrets/trino/localhost.pem ]; then
    echo "Certificate files already exist. Stop and review renewal below."
    exit 1
  fi
  openssl req -new -x509 -sha256 -days 365 \
    -key secrets/trino/localhost.key -out secrets/trino/localhost.crt \
    -subj '/CN=trino' \
    -addext 'subjectAltName=DNS:trino,DNS:localhost,IP:127.0.0.1' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature,keyEncipherment' \
    -addext 'extendedKeyUsage=serverAuth' \
    -addext 'subjectKeyIdentifier=hash' \
    -addext 'authorityKeyIdentifier=keyid:always'
  cat secrets/trino/localhost.key secrets/trino/localhost.crt \
    > secrets/trino/localhost.pem
)
chmod 644 secrets/trino/localhost.pem secrets/trino/localhost.crt
```

Git ignores `secrets/`. The host directories have mode `700`. This protects the key and combined PEM
from other host users. The PEM has mode `644` so Trino (UID 1000) can read the file mount.
The host directories stay private. The separate key has mode `600`.
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

Run `command -v htpasswd` to check availability. Check that it supports bcrypt (`-B`) and cost (`-C`). On macOS it is
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

## Connect

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

## Access rules

`trino/access-control.properties` loads `trino/access-control/rules.json`.
Both paths are mounted read-only. Rules are evaluated first-match within each
section. Explicit rule lists deny unmatched operations; omitting a section can
have permissive defaults. Restart Trino after changing rules. If an editor replaces a bind-mounted file,
recreate the container instead. See [debugging](#debugging).

- `admin` has catalog `owner` access to all current and future catalogs, schema
  ownership, all table privileges, function and procedure privileges, all session
  properties, query execution/view/cancellation, system information read/write,
  and ownership reassignment. System write access includes graceful shutdown.
- `analyst` has read-only catalog access to `pg_lab`, `mssql_lab`, and `system`,
  SELECT on `pg_lab.public`, `mssql_lab.dbo`, and `system.jdbc`, and management
  of own queries only.
  PostgreSQL passthrough functions/procedures and other catalogs are denied.
  Both users additionally have read-only access to the `open-api` catalog; its
  specific rules precede the general administrator grants.
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
docker compose up -d --no-deps --force-recreate trino
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

## Catalogs

### PostgreSQL

[pg_lab.properties](catalog/pg_lab.properties) connects to `postgres:5432/lab_db`.
It uses `${ENV:POSTGRES_USER}` and `${ENV:POSTGRES_PASSWORD}`.
Compose passes both variables from the local `.env` to Trino.
Do not put passwords in a catalog file.

Both Trino users share the source account. Trino rules limit each user's access.
The `analyst` account can read `public`, but not dlt's `api_data` schema.
Use `admin` to query `pg_lab.api_data.users`.

### Live OpenAPI catalog (no ingestion)

The quoted catalog `"open-api"` queries JSONPlaceholder directly, without dlt,
PostgreSQL tables, or persistent API response storage. It exposes `default.users`
and `default.posts` from the public `/users` and `/posts` endpoints.

OpenAPI is a third-party connector, not included in the official Trino image.
`docker/trino/Dockerfile` extends `trinodb/trino:484` with **trino-openapi v2.2**,
whose release explicitly targets Trino 484. The build verifies the release ZIP's
pinned SHA-256 before extraction. It downloads the plugin at build time, so that
step requires access to GitHub. Do not substitute a plugin built for another
Trino release without testing compatibility.

`trino/catalog/open-api.properties` points at the read-only mounted local spec
`trino/openapi/jsonplaceholder.yaml` and `https://jsonplaceholder.typicode.com`.
Only GET operations are declared; no API credentials are required. The connector's
HTTP disk cache is disabled by leaving `http-cache.directory` unset. Requests are
limited to two per second per Trino node. No new Docker volume is introduced.

```sh
docker compose build trino
docker compose up -d --no-deps trino
```

This recreates only Trino; the existing HTTPS certificates, PASSWORD authentication,
and other catalogs are reused. With Superset running from its separate Compose
file, Compose may report those containers as orphans: do not remove them as part
of this operation.

Both `admin` and `analyst` can read API data. The catalog's read-only rule must
remain before the wildcard administrator rule. Matching table rules allow SELECT
only on `users` and `posts`; functions and procedures for this catalog are denied.
INSERT, UPDATE, DELETE, CREATE TABLE, and DROP TABLE are denied even to `admin`.
Existing privileges in other catalogs and query ownership rules are unchanged.

Connect using the normal authenticated Trino CLI or DBeaver session:

```sh
docker compose exec trino trino --server https://localhost:8443 \
  --truststore-path /etc/trino/tls/localhost.crt --user analyst --password
```

```sql
SHOW TABLES FROM "open-api".default;
SELECT count(*) FROM "open-api".default.users; -- normally 10
SELECT count(*) FROM "open-api".default.posts; -- normally 100
SELECT id, user_id, title FROM "open-api".default.posts ORDER BY id LIMIT 10;
```

The hyphen requires double quotes around `"open-api"` in SQL. More read-only
examples are in [openapi_queries.sql](../scripts/openapi_queries.sql). The interactive
`scripts/verify_access_control.py` also checks API SELECT access and denied writes
for both accounts.

Unlike `pg_lab.api_data.users`, these rows are fetched from the API at query time.
Availability, latency, and limits depend on the public service; LIMIT does not
necessarily reduce the number of downloaded records. Trino may use memory and
transient execution/spill space; this is not persistent ingestion. A downstream
client such as Superset can independently cache/export results. The API's user IDs
are not verified identities of the synthetic customers in the source databases.

References: [plugin v2.2 release (Trino 484)](https://github.com/nineinchnick/trino-openapi/releases/tag/v2.2),
[versioned plugin documentation](https://github.com/nineinchnick/trino-openapi/blob/v2.2/README.md),
and [JSONPlaceholder](https://jsonplaceholder.typicode.com/).

### SQL Server

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

Catalogs use static management. After editing a catalog or its environment,
recreate Trino to apply the change. Then use the Trino HTTPS connection:

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

## Certificate renewal

Keep the existing private key if it is secure. First back up the secret files
privately. Check the public certificate without printing the key:

```sh
openssl x509 -in secrets/trino/localhost.crt -noout -dates -ext subjectAltName
```

For intentional renewal, use the certificate command in [first setup](#first-setup).
Remove its existing-certificate guard only after reviewing your backup.
Keep the key and all SAN and X.509 extensions. Replace both `.crt` and combined
`.pem`. Do not send the combined PEM or key to Superset or other clients.

Recreate Trino to refresh file mounts and load the new certificate:

```sh
docker compose up -d --no-deps --force-recreate trino
```

This interrupts running queries. Update any imported client certificates.
If Superset is running, also refresh its public certificate mount:

```sh
docker compose -f compose.yaml -f compose.superset.yaml up -d --no-deps --force-recreate superset
```

No image build or database restart is needed.
See [Superset TLS](../docker/superset/README.md#verified-tls-from-superset-to-trino).

## Debugging

Start with container health and the query ID from the client:

```sh
docker compose ps
docker compose logs --tail 100 trino
```

Log timestamps ending in `Z` use UTC. Local time can have a different offset.
A `QueryMonitor` timeline shows query timing, not each outgoing HTTP request.
For OpenAPI request logging, add these lines to
`trino/catalog/open-api.properties` only when needed:

```properties
openApi.http-client.log.enabled=true
openApi.http-client.log.path=/tmp/openapi-http-logs
```

These are connector-specific properties. Do not add bare
`http-client.log.enabled` to the main server config.
Recreate Trino to reload the catalog, then run one API SELECT.
Inspect the files under `/tmp/openapi-http-logs` inside the container.
They are separate from `docker logs`. Check rotated files too.
These settings follow the [plugin HTTP client guide](https://github.com/nineinchnick/trino-openapi/blob/v2.2/README.md#http-client). Logs may contain URLs or other sensitive details.
Remove temporary logging after the check. The `/tmp` log is not persistent.

If files look stale after a Git checkout or editor save, recreate Trino.
A normal restart does not refresh a bind mount that still points at an old inode.
For permission errors, check the user, catalog, schema, and matching rule first.
Do not grant more access just to make a failing query pass.

