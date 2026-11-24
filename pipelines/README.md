# dlt API users pipeline

[Project overview](../README.md) · [Docker](../docker/README.md) · [SQL examples](../scripts/README.md#federated-queries)

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

## Run

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

## Repeat runs and storage

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

## Verify

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
