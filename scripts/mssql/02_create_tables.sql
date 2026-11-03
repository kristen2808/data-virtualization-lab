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
IF OBJECT_ID(N'lab_mssql.dbo.orders') IS NULL
    EXEC(N'CREATE TABLE lab_mssql.dbo.orders (
        order_id INT NOT NULL PRIMARY KEY,
        customer_id INT NOT NULL,
        order_date DATE NULL,
        status VARCHAR(30) NULL
    )');
IF OBJECT_ID(N'lab_mssql.dbo.order_items') IS NULL
    EXEC(N'CREATE TABLE lab_mssql.dbo.order_items (
        order_item_id INT NOT NULL PRIMARY KEY,
        order_id INT NOT NULL,
        product_id INT NOT NULL,
        quantity INT NULL,
        unit_price DECIMAL(12,2) NULL,
        CONSTRAINT FK_lab_order_items_orders FOREIGN KEY (order_id)
            REFERENCES dbo.orders(order_id)
    )');
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
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
