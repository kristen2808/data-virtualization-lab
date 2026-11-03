-- SQL Server 2022. Connect to master with DBeaver auto-commit ON.
-- CREATE DATABASE cannot run inside an explicit or implicit transaction.
-- Execute this complete batch; no GO or USE is required.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'master'
    THROW 50000, 'Connect directly to master for database creation.', 1;
IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 50001, 'CREATE DATABASE requires auto-commit and no open transaction.', 1;
BEGIN TRY
    IF DB_ID(N'lab_mssql') IS NULL
        EXEC(N'CREATE DATABASE [lab_mssql]');
    IF NOT EXISTS (SELECT 1 FROM sys.databases
                   WHERE name=N'lab_mssql' AND state_desc=N'ONLINE'
                     AND is_read_only=0 AND source_database_id IS NULL)
        THROW 50002, 'lab_mssql must be an online writable non-snapshot database.', 1;
END TRY
BEGIN CATCH
    THROW;
END CATCH;
