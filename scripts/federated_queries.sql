-- Data Virtualization Lab | Federated SQL examples
-- Engine: Trino 484
-- Catalogs: pg_lab (PostgreSQL), mssql_lab (SQL Server)
-- Run individual statements in a Trino SQL client (e.g., DBeaver).

-- 1. Customer orders across PostgreSQL and SQL Server.
-- PostgreSQL: customers | SQL Server: orders
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    o.order_id,
    o.order_date,
    o.status
FROM pg_lab.public.customers AS c
JOIN mssql_lab.dbo.orders AS o
    ON c.customer_id = o.customer_id
ORDER BY o.order_id
LIMIT 20;

-- 2. Number of orders per customer region.
-- Trino joins across catalogs and aggregates the results.
SELECT
    c.region,
    COUNT(o.order_id) AS order_count
FROM pg_lab.public.customers AS c
JOIN mssql_lab.dbo.orders AS o
    ON c.customer_id = o.customer_id
GROUP BY c.region
ORDER BY c.region;

-- 3. API users (loaded to PostgreSQL by dlt) with matching SQL Server orders.
-- DEMO ASSUMPTION: API user id is treated as SQL Server customer_id.
-- These identifiers are not verified to represent the same real-world person.
SELECT
    u.id,
    u.name,
    u.email,
    COUNT(o.order_id) AS order_count
FROM pg_lab.api_data.users AS u
JOIN mssql_lab.dbo.orders AS o
    ON u.id = o.customer_id
GROUP BY u.id, u.name, u.email
ORDER BY u.id;

-- 4. All API users, including those without matching orders.
-- COUNT(o.order_id) returns zero for users with no matching orders.
-- Same demo-only identifier assumption as query 3.
SELECT
    u.id,
    u.name,
    u.email,
    COUNT(o.order_id) AS order_count
FROM pg_lab.api_data.users AS u
LEFT JOIN mssql_lab.dbo.orders AS o
    ON u.id = o.customer_id
GROUP BY u.id, u.name, u.email
ORDER BY u.id;
