# Custom Docker images

This directory contains Dockerfiles for project-specific images. Add a short
description here whenever a new image is introduced.

## dlt

`dlt/Dockerfile` builds a Python 3.12 image with `dlt[postgres]` and the
`pipelines/api_users.py` pipeline. It loads JSONPlaceholder users into
PostgreSQL `lab_db.api_data.users`, merging records by `id` to avoid duplicates.
Credentials are passed through environment variables. The build context excludes
local secrets via `dlt/Dockerfile.dockerignore`.

From the project root:

```sh
docker compose build dlt
docker compose run --rm dlt
```

The container runs once and is removed when it exits. Loaded PostgreSQL data
remains available.
