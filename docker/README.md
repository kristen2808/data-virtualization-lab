# Custom Docker images

This directory contains Dockerfiles for project-specific images. Add a short
description here whenever a new image is introduced.

## dlt

`dlt/Dockerfile` builds a Python 3.12 image with `dlt[postgres]` and the
`pipelines/api_users.py` pipeline. It loads JSONPlaceholder users into
PostgreSQL `lab_db.api_data.users`, merging records by `id` to avoid duplicates.
Credentials are passed through environment variables. The build context excludes
local secrets via `dlt/Dockerfile.dockerignore`.

The service is defined in `compose.dlt.yaml`, which extends the core services
in `compose.yaml`. From the project root:

```sh
docker compose -f compose.yaml -f compose.dlt.yaml build dlt
docker compose -f compose.yaml -f compose.dlt.yaml run --rm dlt
```

The container runs once and is removed when it exits. Loaded PostgreSQL data
remains available.

## Superset

`superset/Dockerfile` extends Apache Superset 6.0.0 with PostgreSQL and Trino
SQLAlchemy drivers. It includes `superset_config.py` and an idempotent
`init_superset.py`; passwords and the secret key are supplied only at runtime.
Metadata persists in PostgreSQL `superset_metadata`. No Redis or Celery is used.

```sh
python3 scripts/setup_superset_secrets.py
docker compose -f compose.yaml -f compose.superset.yaml build superset
docker compose -f compose.yaml -f compose.superset.yaml up -d superset
```

Open <http://localhost:8088>. See the root README for metadata initialization,
local credentials, and safe reruns.

## Trino with OpenAPI

`trino/Dockerfile` extends official Trino 484 with the community OpenAPI plugin
v2.2, built for that exact Trino release. It verifies a pinned SHA-256 checksum.
The plugin JARs are copied into `/usr/lib/trino/plugin/openapi/` at build time,
so they survive container recreation. The read-only mounted
`trino/catalog/open-api.properties` selects it with `connector.name=openapi`;
`trino/openapi/jsonplaceholder.yaml` defines the available endpoints and columns.
The `open-api` catalog reads JSONPlaceholder directly using a local GET-only
OpenAPI specification; HTTP response caching is disabled. Both Trino users have
SELECT-only access to this catalog. Existing authentication and TLS are reused.

```sh
docker compose build trino
docker compose up -d --no-deps trino
```

Use `scripts/openapi_queries.sql` in an authenticated Trino session. See the root
README for external plugin compatibility and public API limitations.
