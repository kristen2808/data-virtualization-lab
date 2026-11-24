# Data Virtualization Lab

A local PoC with Trino 484, PostgreSQL 17, and SQL Server 2022.
Use SQL to join data across databases and a public REST API.
Use dlt to load API data, or query the API directly with OpenAPI.
Apache Superset provides an optional web UI for charts and SQL.

## Services

| Service | Local address | Purpose |
|---|---|---|
| Trino | <https://localhost:8443> | SQL engine with password login |
| PostgreSQL | `localhost:5433` | `lab_db` data and Superset metadata |
| SQL Server | `localhost:1433` | `lab_mssql` data |
| Superset (optional) | <http://localhost:8088> | Charts, dashboards, and SQL Lab |
| dlt (one-off) | No host port | Load API users into PostgreSQL |

Trino runs as both coordinator and worker. Its HTTP port 8080 is not published.
All published ports bind to `127.0.0.1` only.

## Start here

For a new checkout:

1. Install Docker with Compose v2. Use Python 3, OpenSSL, and `htpasswd` for setup.
2. Follow [Docker setup](docker/README.md#first-setup) to create your local `.env`.
3. Create the [Trino certificate and login files](trino/README.md#first-setup).
4. Start the core services:

   ```sh
   docker compose build trino
   docker compose up -d
   docker compose ps
   ```

5. Create the [sample data](scripts/README.md#sample-data).
6. Connect with the [Trino CLI or DBeaver](trino/README.md#connect).

For an existing setup, keep your `.env`, secrets, and database volumes.
Do not repeat password or certificate setup unless you want to change them.

## Documentation

| Guide | Contents |
|---|---|
| [Docker](docker/README.md) | Compose files, images, ports, volumes, and service commands |
| [Trino](trino/README.md) | HTTPS, users, access rules, catalogs, and debugging |
| [Scripts](scripts/README.md) | Sample data, SQL examples, checks, and metadata database setup |
| [Pipelines](pipelines/README.md) | dlt REST source, merge behavior, and repeat runs |
| [Superset](docker/superset/README.md) | Metadata, app secrets, startup, and verified Trino TLS |

## Optional services

Load API users into PostgreSQL:

```sh
docker compose -f compose.yaml -f compose.dlt.yaml build dlt
docker compose -f compose.yaml -f compose.dlt.yaml run --rm dlt
```

After [Superset setup](docker/superset/README.md#first-setup):

```sh
docker compose -f compose.yaml -f compose.superset.yaml up -d superset
```

## Data and access

- `pg_lab`: PostgreSQL data, including dlt data in `api_data`.
- `mssql_lab`: SQL Server tables in `lab_mssql`.
- `"open-api"`: live JSONPlaceholder users and posts. No ingestion or HTTP disk cache.
- `admin`: broad Trino access. The OpenAPI catalog is read-only even for this user.
- `analyst`: SELECT on `pg_lab.public`, `mssql_lab.dbo`, and the OpenAPI tables.
  It can read JDBC metadata and manage its own queries.

PostgreSQL, Trino, and Superset accounts are separate.
See [Trino access rules](trino/README.md#access-rules) for the exact limits.

## Stop safely

Stop containers but keep them:

```sh
docker compose stop
```

Stop and remove the core containers. Keep database volumes:

```sh
docker compose down
```

Stop [Superset separately](docker/superset/README.md#stop) if it is running.
Never use `down -v` when you need to keep database data.
Keep `.env` and `secrets/` out of Git. This is a local lab, not a production setup.
