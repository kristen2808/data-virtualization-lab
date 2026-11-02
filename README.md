# Local Trino PoC

Requirements: a running Docker Engine and Docker Compose v2.

The `trino` service uses the official `trinodb/trino:484` image and a container
named `trino`. The default image configuration runs both the coordinator
and worker in a single container. Port 8080 is available only on localhost.

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
logs). Open the web UI at <http://localhost:8080>.
If prompted for a username, choose any name; no password is required.

Check the HTTP API and query the built-in `tpch` catalog's sample data:

```sh
curl --fail http://localhost:8080/v1/info
docker compose exec -T trino trino --execute 'SELECT count(*) FROM tpch.sf1.nation'
```

The query should return `25`.

Verify the PostgreSQL connection through the Trino CLI:

```sh
docker compose exec -T trino trino --execute 'SHOW CATALOGS'
docker compose exec -T trino trino --execute 'SHOW SCHEMAS FROM pg_lab'
```

The first command should list `pg_lab`; the second should include the `public`
schema. These commands do not create tables or data.

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
