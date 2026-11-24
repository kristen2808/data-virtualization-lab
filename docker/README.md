# Docker setup and images

[Project overview](../README.md) · [Trino](../trino/README.md) · [Superset](superset/README.md)

Run all commands below from the project root.

## Compose files

| File | Services |
|---|---|
| [compose.yaml](../compose.yaml) | `trino`, `postgres`, `sqlserver` |
| [compose.dlt.yaml](../compose.dlt.yaml) | One-off `dlt` job |
| [compose.superset.yaml](../compose.superset.yaml) | `superset` and `superset-init` |

Pass `compose.yaml` first when combining files. This keeps the same project,
network, database services, and volume names. Do not change the project name
with `-p` unless you want a separate environment and separate volumes.

## First setup

Requirements: Docker Engine or Docker Desktop with Compose v2.
Use Python 3, OpenSSL with `-addext`, and bcrypt-capable `htpasswd` for Trino setup.
Builds need internet access to Docker Hub, package repositories, and GitHub.

For a new checkout only:

```sh
cp .env.example .env
chmod 600 .env
```

Edit `.env` locally. Never overwrite an existing file with the example.

| Variable | Used by |
|---|---|
| `POSTGRES_USER` | PostgreSQL, Trino `pg_lab`, and dlt |
| `POSTGRES_PASSWORD` | The same PostgreSQL connections |
| `MSSQL_USER` | Trino `mssql_lab`; defaults to `sa` |
| `MSSQL_SA_PASSWORD` | SQL Server `sa` and the current Trino connector |

Use strong, unique passwords. Quote values with single quotes if they contain
`$` or `#`. The empty SQL Server password in the example must be filled in.
Changing `.env` does not rotate passwords in an existing database volume.

PostgreSQL creates `POSTGRES_USER` as a superuser on its first initialization.
The lab defaults to `lab_user`. SQL Server uses `sa` for this PoC.
Use separate limited technical accounts for a real deployment.
Do not give these source credentials to read-only Trino users.

Next, create the [Trino secrets and certificate](../trino/README.md#first-setup).
Trino needs these files before its container can start.
Superset has [separate secrets](superset/README.md#local-secrets).

## Start and check

```sh
docker compose config --quiet
docker compose build trino
docker compose up -d
docker compose ps
```

`config --quiet` validates without printing secret values.
Do not share expanded Compose output or container environment dumps.

Check all optional files together:

```sh
docker compose -f compose.yaml -f compose.dlt.yaml -f compose.superset.yaml config --quiet
```

This also requires the Superset secret files to exist.
The `pipelines` profile keeps dlt out of a normal `up` command.

## Ports and storage

| Service | Container name | Host port | Internal address | Data volume |
|---|---|---|---|---|
| Trino | `trino` | `127.0.0.1:8443` | `trino:8443` | None added |
| PostgreSQL | `trino-postgre` | `127.0.0.1:5433` | `postgres:5432` | `postgres_data` |
| SQL Server | `sqlserver22` | `127.0.0.1:1433` | `sqlserver:1433` | `sqlserver_data` |
| Superset | Compose-generated | `127.0.0.1:8088` | `superset:8088` | Uses PostgreSQL metadata |

Compose prefixes volume names with the project name.
PostgreSQL stores data in `/var/lib/postgresql/data`.
SQL Server stores data in `/var/opt/mssql`.
Superset metadata lives in `superset_metadata` in the PostgreSQL volume.

Use service names with `docker compose`. Use container names with `docker exec`.
Containers share the default Compose network. They do not use the host ports
to connect to each other.

## Custom images

### Trino and OpenAPI

[trino/Dockerfile](trino/Dockerfile) extends `trinodb/trino:484`.
It adds community OpenAPI plugin **v2.2**, built for Trino 484.
The build checks the ZIP file against a pinned SHA-256 checksum.
JAR files go into `/usr/lib/trino/plugin/openapi/`.
They are part of the image and survive container recreation.

The image tag is `data-virtualization-lab-trino:484-openapi-2.2`.
The build context contains only the Dockerfile and its ignore file.
Catalogs, access rules, and TLS files are read-only runtime mounts.
See [catalogs](../trino/README.md#catalogs) for details.

### dlt

[dlt/Dockerfile](dlt/Dockerfile) uses Python 3.12 and `dlt[postgres]==1.32.0`.
It runs [api_users.py](../pipelines/api_users.py) as a non-root user.
[dlt/Dockerfile.dockerignore](dlt/Dockerfile.dockerignore) limits the build context.
Local secrets are not copied into the image.

```sh
docker compose -f compose.yaml -f compose.dlt.yaml build dlt
docker compose -f compose.yaml -f compose.dlt.yaml run --rm dlt
```

`--rm` removes the job container after it exits. PostgreSQL data stays.
See the [pipeline guide](../pipelines/README.md).

### Superset

[superset/Dockerfile](superset/Dockerfile) extends Apache Superset **6.0.0**.
It adds PostgreSQL and Trino SQLAlchemy drivers.
The init service runs migrations and creates a missing admin account.
The web service uses Gunicorn. No Redis or Celery service is added.
See [Superset setup](superset/README.md) before starting it.

## SQL Server on Apple Silicon

SQL Server uses `mcr.microsoft.com/mssql/server:2022-latest` with
`platform: linux/amd64`, `ACCEPT_EULA=Y`, and `MSSQL_PID=Developer`.
The tag can change within the 2022 release line.
Developer edition is for development and testing.

Docker must emulate AMD64 on Apple Silicon. Startup can be slow or fail.
Microsoft does not support Rosetta/QEMU execution of this image.
SQL Server alone needs at least 2 GB RAM. Allow more for the full lab.
If emulation fails, use an x86-64 Linux host for SQL Server.

```sh
docker compose up -d --no-deps sqlserver
docker compose logs --tail 100 sqlserver
docker compose exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -C -Q 'SELECT @@VERSION;'
```

Wait for `SQL Server is now ready for client connections` in the log.
`sqlcmd` prompts for the password. `-C` trusts the local SQL Server certificate.
This exception is for the local PoC only.
Create sample tables with the [SQL scripts](../scripts/README.md#sample-data).

## Apply changes and stop

A process restart does not apply new environment variables or mounts.
After a Compose change, run `up -d` for the affected service.
After a Dockerfile change, build it first.

```sh
docker compose build trino
docker compose up -d --no-deps trino
```

Git or an editor can replace a bind-mounted file with a new inode.
If the container sees old or missing files, recreate it:

```sh
docker compose up -d --no-deps --force-recreate trino
```

This interrupts active Trino queries. See [debugging](../trino/README.md#debugging).
If Superset is running, base-only commands can report orphan containers.
Do not use `--remove-orphans` to remove them by accident.

```sh
docker compose stop
docker compose down
```

`stop` keeps containers. `down` removes core containers and their network when possible.
Named database volumes stay. Stop [Superset](superset/README.md#stop) separately.
Do not use `down -v` to fix a configuration issue.

## Sources

- [Trino image](https://trino.io/docs/current/installation/containers.html)
- [OpenAPI v2.2 release](https://github.com/nineinchnick/trino-openapi/releases/tag/v2.2)
- [SQL Server container support](https://learn.microsoft.com/en-us/sql/linux/containers/deploy?view=sql-server-ver16)
