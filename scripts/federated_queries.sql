-- Run in Trino: join PostgreSQL customers with SQL Server orders.
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    o.order_id,
    o.order_date,
    o.status
FROM pg_lab.public.customers c
JOIN mssql_lab.dbo.orders o
    ON c.customer_id = o.customer_id
ORDER BY o.order_id
LIMIT 20;
