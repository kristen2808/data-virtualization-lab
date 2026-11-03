# Synthetic data for the virtualization PoC

Run these files in DBeaver against the source databases, **not through Trino**.
No passwords are included. Use the existing local connection credentials.
Save SQL files as UTF-8 so Czech city and region names are preserved.
The existing `verify_access_control.py` script is unrelated to this seed dataset.

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
explicit transactions, `TRY/CATCH`, rollback, and `THROW`. Target-table seed\noperations use a nested `sp_executesql` scope so binding/compilation errors can\nalso be caught and rolled back. The client must not
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

After a SQL Server catalog is configured in a separate task, a direct Trino
anti-join can verify actual cross-server relationships. Replace `mssql_lab`
with that catalog's real name; it does not exist as part of these scripts.
Run as `admin`: the current `analyst` policy intentionally does not allow it.

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

These scripts have been prepared for review; they have not been executed against
the databases as part of this task.

References: [PostgreSQL 17 error handling](https://www.postgresql.org/docs/17/plpgsql-errors-and-messages.html),
[SQL Server XACT_ABORT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql?view=sql-server-ver16),
and [SQL Server CREATE DATABASE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql?view=sql-server-ver16).
