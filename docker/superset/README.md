# Apache Superset

[Project overview](../../README.md) · [Docker](../README.md) · [Trino](../../trino/README.md)

## First setup

`compose.superset.yaml` adds `superset` and the one-off `superset-init` service.
Both use our custom image based on **`apache/superset:6.0.0`**, with
`psycopg2-binary==2.9.11`, `trino[sqlalchemy]==0.340.0`, and SQLAlchemy 1.4.54.
The application connects as database role `superset` to
`postgres:5432/superset_metadata`. `SUPERSET_DB_PASSWORD` is read from the
existing `secrets/superset/metadata.env`. It never uses SQLite or `lab_db`
for its metadata.

First create the [metadata database](../../scripts/README.md#superset-metadata-database).
It uses the existing PostgreSQL service. Run all commands from the project root.

## Local secrets

Keep the metadata role's actual password in ignored
`secrets/superset/metadata.env` as `SUPERSET_DB_PASSWORD`.
Create this file in a local editor if it does not exist. Use the password set
by the metadata script. Do not store a SCRAM verifier here: the app needs the
actual login password. Single-quote values containing `$` or `#`.
Keep the file mode `600` and the `secrets/` directories mode `700`.
Never overwrite an existing credentials file during setup.

Create application secrets without overwriting existing values:

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

## Start and check

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
automatically. Trino requires its existing HTTPS/password credentials and
the explicit TLS trust configuration described below.

## Verified TLS from Superset to Trino

Inside Docker, Superset connects to `https://trino:8443`. Trino's self-signed
certificate must include `DNS:trino`, `DNS:localhost`, and `IP:127.0.0.1` in its SAN.
The [Trino setup command](../../trino/README.md#first-setup) preserves the key and includes
critical basic constraints/key usage, server authentication EKU, and subject/authority
key identifiers for strict Python TLS validation. The certificate is a TLS server
certificate (`CA:FALSE`), explicitly trusted by this local client.

`compose.superset.yaml` mounts only the public certificate into the web service:

```yaml
- ./secrets/trino/localhost.crt:/app/certs/trino.crt:ro
```

The private key and combined PEM stay in Trino's ignored secrets directory;
neither is mounted in Superset. `superset-init` only uses PostgreSQL metadata
and does not need this certificate.

For the Trino database connection in Superset, use host `trino`, port `8443`,
your existing Trino username/password, and the desired catalog/schema. In the
connection's **Advanced / Other / Engine Parameters**, set:

```json
{
  "connect_args": {
    "http_scheme": "https",
    "verify": "/app/certs/trino.crt"
  }
}
```

Merge this with any existing engine parameters. Keep certificate and hostname
verification enabled. A self-signed certificate is not automatically trusted
merely because it is mounted. This per-connection setting avoids changing trust
for unrelated HTTP clients. The TLS fix does not update stored database
connections or credentials automatically; apply this setting in the UI if missing.

After intentional certificate renewal, update both `localhost.crt` and
`localhost.pem` while preserving the key. Write existing files in place so
individual bind mounts see their new content; after atomic replacement, recreate
the affected containers to refresh those mounts. Restart only the affected services:

```sh
docker compose up -d --no-deps --force-recreate trino
docker compose -f compose.yaml -f compose.superset.yaml up -d --no-deps --force-recreate superset
```

No image rebuild, metadata initialization, database restart, or volume deletion is
needed. A new certificate must also replace the old trusted public certificate
in clients that imported it (for example, DBeaver or a Java truststore).

Verify from the Superset container without passwords or SQL execution:

```sh
docker compose -f compose.yaml -f compose.superset.yaml exec -T superset python -c \
  'import requests; r = requests.get("https://trino:8443/v1/info", verify="/app/certs/trino.crt", timeout=10); r.raise_for_status(); print(r.status_code)'
```

Verify the host endpoint on macOS:

```sh
curl --fail --cacert secrets/trino/localhost.crt https://localhost:8443/v1/info
```

Both checks should succeed. The `/v1/info` endpoint is public; these checks verify
TLS connectivity and trust, not SQL authorization.

## Verify metadata

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

## Stop

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
