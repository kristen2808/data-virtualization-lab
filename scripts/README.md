# SQL scripts and checks

[Project overview](../README.md) · [Trino](../trino/README.md) · [dlt pipeline](../pipelines/README.md)

Run seed SQL files in DBeaver against the source databases, **not through Trino**.
No passwords are included. Use the existing local connection credentials.
Save SQL files as UTF-8 so Czech city and region names are preserved.
The seed scripts below run directly against PostgreSQL and SQL Server.
`federated_queries.sql` runs through Trino; `verify_access_control.py` tests
Trino permissions interactively.

## Federated queries

Open `federated_queries.sql` in DBeaver using the **Trino HTTPS connection**
(`localhost:8443`), not a direct PostgreSQL or SQL Server connection.
Authenticate with TLS certificate validation enabled. Queries 1–2 work for
`admin` and `analyst`; queries 3–4 require `admin` under the current access policy.
Both `pg_lab` and `mssql_lab` catalogs must be loaded and the source seed data
must already exist.

The file contains four read-only examples: customer orders across both databases,
order counts by region, and INNER/LEFT JOINs between dlt-loaded API users and
SQL Server orders. Run statements individually; they can be repeated safely.
Queries 3–4 require the dlt pipeline to have populated `pg_lab.api_data.users`.
Matching API user `id` to `customer_id` is a demo assumption, not a verified
real-world identity relationship. The joins demonstrate federation across sources.

## Live OpenAPI queries

`openapi_queries.sql` runs through the Trino HTTPS connection as either `admin`
or `analyst`. It reads live JSONPlaceholder users/posts and joins them within
the `"open-api"` catalog. Double-quote the catalog name because it contains a
hyphen. No seed scripts or dlt ingestion are needed, and no API rows are stored
in the source databases. Both users are denied writes and DDL for this catalog.
The public API must be reachable from Trino; it normally returns 10 users and
100 posts. The interactive ACL checks also cover this catalog's read-only rules.

## Access control checks

From the project root, run:

```sh
python3 scripts/verify_access_control.py
```

The script prompts for both Trino passwords without displaying them. It checks
catalog visibility, query ownership, and PostgreSQL read/write permissions using
new fixture tables named `acl_probe_<uuid>` that it removes afterward.
It does not seed the dataset below or test SQL Server DML permissions.
These are ordinary tables, not SQL TEMP tables. The script cleans them up in
`finally`. If the process is killed or the server is unreachable, cleanup can
fail. Remove only the exact reported probe names after reviewing the error.
Query cancellation tests use completed queries. They check REST authorization,
not interruption of a running workload. OpenAPI checks also test denied writes.
A failing check does not change permissions.
See [access rules](../trino/README.md#access-rules) for details.

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

Keep the actual login password in ignored `secrets/superset/metadata.env`
under `SUPERSET_DB_PASSWORD` for the app. Use mode `600` and private directories
with mode `700`. Do not replace it on a rerun.
See [Superset setup](../docker/superset/README.md#local-secrets).
A SCRAM verifier can initialize PostgreSQL, but cannot replace the actual
login password in the Superset app's environment file.

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

## Sample data

## Execution order

Use a dedicated SQL editor with **auto-commit enabled**, no open transaction,
and stop-on-error behavior. Execute each file as a complete statement/batch
(select the whole file and execute it); do not execute individual lines inside
`DO`, `TRY/CATCH`, or transaction blocks. The files contain no `GO` or `USE`.
If DBeaver tries to split T-SQL batches, use execution of the whole selected SQL
statement rather than delimiter-based script execution.

| Order | File | Direct DBeaver connection / database |
|---|---|---|
| 1 | `postgres/01_create_tables.sql` | PostgreSQL `localhost:5433`, `lab_db`, `lab_user` |
| 2 | `postgres/02_insert_data.sql` | Same PostgreSQL connection |
| 3 | `mssql/01_create_database.sql` | SQL Server `localhost:1433`, database `master`, login `sa` |
| 4 | `mssql/02_create_tables.sql` | **New/reconnected SQL Server connection with database `lab_mssql`** |
| 5 | `mssql/03_insert_data.sql` | Same `lab_mssql` connection |

After step 3, refresh DBeaver's database navigator and create or reconnect the
connection with `lab_mssql` explicitly configured. Changing the navigator's
selection alone may not change an existing editor's connection. Each script
checks the actual database and fails on a wrong connection. PostgreSQL names
are qualified with `public`; SQL Server persistent tables use three-part names.
No new PostgreSQL database or Trino catalog is created.

## Transactions and existing objects

PostgreSQL files each consist of one atomic `DO` statement: an unhandled error
rolls back that statement. SQL Server table/seed files use `SET XACT_ABORT ON`,
explicit transactions, `TRY/CATCH`, rollback, and `THROW`. Target-table seed
operations use a nested `sp_executesql` scope so binding/compilation errors can
also be caught and rolled back. The client must not
wrap them in an existing transaction. If the client leaves a PostgreSQL session
in an aborted transaction, issue `ROLLBACK` before retrying.

**Exception:** SQL Server `CREATE DATABASE` must run in auto-commit mode and
cannot be rolled back as part of the later table/data transactions. A successfully
created database remains if a later file fails. The script never drops it.
Transactions are per file and per server; there is no distributed transaction.

Table creation is conditional. Both creation and seed scripts validate column
names/order, types, sizes, nullability, primary keys, and the SQL Server foreign
key. Defaults, generated/identity columns, user triggers, check constraints,
additional unique indexes, and other incompatible features are rejected.
The scripts intentionally accept only a narrow fixture-compatible structure,
not arbitrary application tables. No existing object is altered or removed.
Ordinary non-unique indexes are allowed. Metadata inspection requires sufficient
permissions (the specified source database owner/`sa` connections are suitable).

If table names already belong to application data, **do not repurpose them**.
Review the error and use a separate lab environment. No script repairs a
conflict by deleting or updating rows.

## Deterministic dataset

| Table | ID range | Final row count |
|---|---|---:|
| PostgreSQL `public.customers` | 1–1000 | 1000 |
| PostgreSQL `public.products` | 1–200 | 200 |
| SQL Server `lab_mssql.dbo.orders` | 1–10000 | 10000 |
| SQL Server `lab_mssql.dbo.order_items` | 1–30000 | 30000 |

PostgreSQL uses `generate_series` and fixed arrays of 14 paired Czech cities
and regions, four customer segments, and eight product categories. Names are
synthetic (`Customer 0001`, `Product 001`), not personal data.

SQL Server builds 1–10000 from four cross-joined decimal digit sets and creates
three items per order. No random functions, current timestamps, sequences,
external generators, or libraries are used.

- Customer ID: `((order_id - 1) * 37) % 1000 + 1`.
- Order date: `2025-01-01 + (((order_id - 1) * 17) % 730)` days.
- Status cycles through `new`, `paid`, `shipped`, `delivered`, `cancelled`.
- Item ID: `(order_id - 1) * 3 + slot`, where slot is 1, 2, or 3.
- Product ID: `((order_item_id - 1) * 17) % 200 + 1`.
- Quantity: `order_item_id % 5 + 1`.
- Product price: `10 + product_id * 3.75 + (product_id % 7) * 0.13`.
- Item price: product price multiplied by `1 + (order_item_id % 11 - 5) / 100`,
  rounded to two decimals with decimal arithmetic (a discount/surcharge of up to 5%).

The formulas share the same customer/product ID domains on both servers.
Only `order_items.order_id -> orders.order_id` is a physical foreign key;
there are no cross-server foreign keys. Cross-server consistency assumes that
PostgreSQL initialization completed and its fixture has not subsequently changed.

## Verify counts and relationships

Run on PostgreSQL `lab_db`:

```sql
SELECT 'customers' AS table_name, count(*) AS row_count,
       min(customer_id) AS min_id, max(customer_id) AS max_id
FROM public.customers
UNION ALL
SELECT 'products', count(*), min(product_id), max(product_id)
FROM public.products;
```

Expected: `customers / 1000 / 1 / 1000`, `products / 200 / 1 / 200`.
With the verified primary keys, these counts and bounds prove that both integer
ID domains are complete, without gaps.

Run on SQL Server `lab_mssql`:

```sql
SELECT 'orders' AS table_name, COUNT_BIG(*) AS row_count FROM lab_mssql.dbo.orders
UNION ALL
SELECT 'order_items', COUNT_BIG(*) FROM lab_mssql.dbo.order_items;
-- Expected: 10000 and 30000.

SELECT MIN(order_date) AS first_order, MAX(order_date) AS last_order,
       COUNT(DISTINCT YEAR(order_date)) AS years_present
FROM lab_mssql.dbo.orders;
-- Expected: 2025-01-01, 2026-12-31, 2.

SELECT COUNT_BIG(*) AS orphan_order_items
FROM lab_mssql.dbo.order_items i
LEFT JOIN lab_mssql.dbo.orders o ON o.order_id=i.order_id
WHERE o.order_id IS NULL;

SELECT COUNT_BIG(*) AS invalid_customer_references
FROM lab_mssql.dbo.orders
WHERE customer_id NOT BETWEEN 1 AND 1000;

SELECT COUNT_BIG(*) AS invalid_product_references
FROM lab_mssql.dbo.order_items
WHERE product_id NOT BETWEEN 1 AND 200;

SELECT COUNT_BIG(*) AS orders_without_three_items
FROM lab_mssql.dbo.orders o
LEFT JOIN lab_mssql.dbo.order_items i ON i.order_id=o.order_id
GROUP BY o.order_id
HAVING COUNT(i.order_item_id) <> 3;
-- Expected: the first three checks return 0; the grouped check returns no rows.
```

The PostgreSQL complete-domain check plus SQL Server range checks establish
cross-server ID consistency without linked servers or a new Trino catalog.
Separate checks are not a single atomic snapshot; run them without concurrent
fixture modifications.

Use these Trino anti-joins to check the cross-server relationships. Both `admin` and `analyst`
can run these SELECTs under the current policy. The seed scripts themselves
do not configure or reload Trino catalogs.

```sql
SELECT count(*) AS missing_customers
FROM mssql_lab.dbo.orders o
LEFT JOIN pg_lab.public.customers c ON c.customer_id=o.customer_id
WHERE c.customer_id IS NULL;

SELECT count(*) AS missing_products
FROM mssql_lab.dbo.order_items i
LEFT JOIN pg_lab.public.products p ON p.product_id=i.product_id
WHERE p.product_id IS NULL;
-- Expected: both 0.
```

## Safe reruns

Rerun all files in the same order and with the same database connections.
Existing exact fixture rows are preserved; only missing rows are inserted.
Before inserts, each seed script compares all existing target rows with its
expected dataset. Any differing value, colliding ID, or row outside the fixture
causes an error and rollback. It never silently accepts mismatched rows or
performs an update/upsert. Final counts must match exactly.

Application-level locks serialize these scripts; seed scripts additionally lock
the target tables while checking and inserting. Run during an idle lab session.
If a file fails, stop and inspect the error; do not disable checks or delete data.
A failed later file does not undo an already committed earlier file. Fix the
underlying issue, then rerun. No Compose/Trino changes or volume cleanup are needed.

References: [PostgreSQL 17 error handling](https://www.postgresql.org/docs/17/plpgsql-errors-and-messages.html),
[SQL Server XACT_ABORT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql?view=sql-server-ver16),
and [SQL Server CREATE DATABASE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql?view=sql-server-ver16).
