-- SQL Server 2022. Connect directly to lab_mssql; execute as one complete batch.
-- Do not execute fragments or let the client continue after errors. No GO/USE needed.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'lab_mssql'
    THROW 50000, 'Connect directly to lab_mssql before running this script.', 1;
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 50001, 'Finish the existing transaction and enable auto-commit first.', 1;
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @lock_result int;
    EXEC @lock_result = sys.sp_getapplock
        @Resource=N'lab_fixture_v1', @LockMode=N'Exclusive',
        @LockOwner=N'Transaction', @LockTimeout=10000;
    IF @lock_result < 0
        THROW 50002, 'Could not acquire the fixture initialization lock.', 1;
IF OBJECT_ID(N'lab_mssql.dbo.orders',N'U') IS NULL
   OR OBJECT_ID(N'lab_mssql.dbo.order_items',N'U') IS NULL
    THROW 50003, 'Expected dbo.orders and dbo.order_items user tables.', 1;
DECLARE @expected TABLE (
    table_name sysname, column_name sysname, type_name sysname,
    max_length smallint, precision_value tinyint, scale_value tinyint,
    is_nullable bit, column_id int
);
INSERT INTO @expected VALUES
    (N'orders',N'order_id',N'int',4,10,0,0,1),
    (N'orders',N'customer_id',N'int',4,10,0,0,2),
    (N'orders',N'order_date',N'date',3,10,0,1,3),
    (N'orders',N'status',N'varchar',30,0,0,1,4),
    (N'order_items',N'order_item_id',N'int',4,10,0,0,1),
    (N'order_items',N'order_id',N'int',4,10,0,0,2),
    (N'order_items',N'product_id',N'int',4,10,0,0,3),
    (N'order_items',N'quantity',N'int',4,10,0,1,4),
    (N'order_items',N'unit_price',N'decimal',9,12,2,1,5);
DECLARE @actual TABLE (
    table_name sysname, column_name sysname, type_name sysname,
    max_length smallint, precision_value tinyint, scale_value tinyint,
    is_nullable bit, column_id int
);
INSERT INTO @actual
SELECT t.name,c.name,ty.name,c.max_length,c.precision,c.scale,c.is_nullable,c.column_id
FROM lab_mssql.sys.tables t
JOIN lab_mssql.sys.schemas s ON s.schema_id=t.schema_id
JOIN lab_mssql.sys.columns c ON c.object_id=t.object_id
JOIN lab_mssql.sys.types ty ON ty.user_type_id=c.user_type_id
WHERE s.name=N'dbo' AND t.name IN (N'orders',N'order_items');
IF EXISTS(SELECT * FROM @expected EXCEPT SELECT * FROM @actual)
   OR EXISTS(SELECT * FROM @actual EXCEPT SELECT * FROM @expected)
    THROW 50004, 'Incompatible column names, types, order or nullability.', 1;
IF EXISTS (
    SELECT 1 FROM lab_mssql.sys.columns
    WHERE object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
      AND (is_identity=1 OR is_computed=1 OR default_object_id<>0
           OR rule_object_id<>0 OR is_sparse=1 OR generated_always_type<>0)
) OR EXISTS (
    SELECT 1 FROM lab_mssql.sys.triggers
    WHERE parent_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
) OR EXISTS (
    SELECT 1 FROM lab_mssql.sys.security_predicates
    WHERE target_object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
) OR EXISTS (
    SELECT 1 FROM lab_mssql.sys.check_constraints
    WHERE parent_object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
) OR EXISTS (
    SELECT 1 FROM lab_mssql.sys.tables
    WHERE object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
      AND (temporal_type<>0 OR is_memory_optimized=1)
) OR EXISTS (
    SELECT 1 FROM lab_mssql.sys.indexes
    WHERE object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
      AND (is_disabled=1 OR (is_unique=1 AND is_primary_key=0))
)
    THROW 50005, 'Unsupported identity, computed/default columns, triggers, checks or table/index options.', 1;
IF (SELECT count(*) FROM lab_mssql.sys.key_constraints k
    WHERE k.parent_object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))
      AND k.type=N'PK'
      AND (SELECT count(*) FROM lab_mssql.sys.index_columns ic
           WHERE ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id AND ic.key_ordinal>0)=1
      AND EXISTS(SELECT 1 FROM lab_mssql.sys.index_columns ic
                 WHERE ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id
                   AND ic.key_ordinal=1 AND ic.column_id=1)) <> 2
    THROW 50006, 'Expected a single-column primary key on each ID column.', 1;
IF (SELECT count(*) FROM lab_mssql.sys.foreign_keys
    WHERE parent_object_id IN (OBJECT_ID(N'lab_mssql.dbo.orders'),OBJECT_ID(N'lab_mssql.dbo.order_items'))) <> 1
   OR NOT EXISTS (
    SELECT 1 FROM lab_mssql.sys.foreign_keys f
    WHERE f.parent_object_id=OBJECT_ID(N'lab_mssql.dbo.order_items')
      AND f.referenced_object_id=OBJECT_ID(N'lab_mssql.dbo.orders')
      AND f.is_disabled=0 AND f.is_not_trusted=0
      AND f.delete_referential_action=0 AND f.update_referential_action=0
      AND (SELECT count(*) FROM lab_mssql.sys.foreign_key_columns fc WHERE fc.constraint_object_id=f.object_id)=1
      AND EXISTS (SELECT 1 FROM lab_mssql.sys.foreign_key_columns fc
                  WHERE fc.constraint_object_id=f.object_id
                    AND fc.parent_column_id=2 AND fc.referenced_column_id=1)
   )
    THROW 50007, 'Expected only the enabled, trusted order_items.order_id -> orders.order_id foreign key.', 1;
-- Compile target-table operations in a nested scope so CATCH can roll back binding errors.
EXEC sys.sp_executesql N'-- Hold locks until commit: collision checks and inserts must see one stable state.
DECLARE @existing_count bigint;
SELECT @existing_count=COUNT_BIG(*) FROM lab_mssql.dbo.orders WITH (TABLOCKX,HOLDLOCK);
SELECT @existing_count=COUNT_BIG(*) FROM lab_mssql.dbo.order_items WITH (TABLOCKX,HOLDLOCK);
CREATE TABLE #expected_orders (
    order_id int PRIMARY KEY, customer_id int NOT NULL, order_date date,
    status varchar(30) COLLATE Latin1_General_100_BIN2
);
CREATE TABLE #expected_items (
    order_item_id int PRIMARY KEY, order_id int NOT NULL,
    product_id int NOT NULL, quantity int, unit_price decimal(12,2)
);
;WITH digits(n) AS (
    SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(n)
), numbers AS (
    SELECT 1+a.n+10*b.n+100*c.n+1000*d.n AS n
    FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits d
)
INSERT INTO #expected_orders
SELECT n, ((n-1)*37)%1000+1,
       DATEADD(day,((n-1)*17)%730,CONVERT(date,''20250101'',112)),
       CASE (n-1)%5 WHEN 0 THEN ''new'' WHEN 1 THEN ''paid''
            WHEN 2 THEN ''shipped'' WHEN 3 THEN ''delivered'' ELSE ''cancelled'' END
FROM numbers;
INSERT INTO #expected_items
SELECT item_id, o.order_id, p.product_id, item_id%5+1,
       CAST(ROUND((10 + p.product_id*3.75 + (p.product_id%7)*0.13)
                  * (1 + CAST(item_id%11-5 AS decimal(12,4))/100),2) AS decimal(12,2))
FROM #expected_orders o CROSS JOIN (VALUES(1),(2),(3)) v(slot)
CROSS APPLY (SELECT (o.order_id-1)*3+v.slot AS item_id) i
CROSS APPLY (SELECT ((item_id-1)*17)%200+1 AS product_id) p;
IF EXISTS (
    SELECT order_id,customer_id,order_date,CONVERT(varbinary(30),status)
    FROM lab_mssql.dbo.orders
    EXCEPT SELECT order_id,customer_id,order_date,CONVERT(varbinary(30),status) FROM #expected_orders
) OR EXISTS (
    SELECT order_item_id,order_id,product_id,quantity,unit_price FROM lab_mssql.dbo.order_items
    EXCEPT SELECT order_item_id,order_id,product_id,quantity,unit_price FROM #expected_items
)
    THROW 50008, ''Existing rows differ from the deterministic fixture; nothing will be overwritten.'', 1;
INSERT INTO lab_mssql.dbo.orders (order_id,customer_id,order_date,status)
SELECT e.order_id,e.customer_id,e.order_date,e.status FROM #expected_orders e
WHERE NOT EXISTS(SELECT 1 FROM lab_mssql.dbo.orders t WHERE t.order_id=e.order_id);
INSERT INTO lab_mssql.dbo.order_items (order_item_id,order_id,product_id,quantity,unit_price)
SELECT e.order_item_id,e.order_id,e.product_id,e.quantity,e.unit_price FROM #expected_items e
WHERE NOT EXISTS(SELECT 1 FROM lab_mssql.dbo.order_items t WHERE t.order_item_id=e.order_item_id);
IF (SELECT COUNT_BIG(*) FROM lab_mssql.dbo.orders)<>10000
   OR (SELECT COUNT_BIG(*) FROM lab_mssql.dbo.order_items)<>30000
    THROW 50009, ''Unexpected final row counts.'', 1;
DROP TABLE #expected_items;
DROP TABLE #expected_orders;
';
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
