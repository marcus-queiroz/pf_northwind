-- ============================================================
-- 03_cleanup.sql
-- Remove os bancos criados pelos scripts deste projeto:
-- Northwind (fonte OLTP, criada por 00_create_northwind_source.sql)
-- e NorthwindDW (pipeline bronze/silver/gold, criado por 01_setup.sql
-- e 02_build_and_load.sql).
--
-- Seguro rodar mesmo se um ou os dois já não existirem.
-- Não há volta: os dados são apagados. Para reconstruir, rode
-- 00_create_northwind_source.sql -> 01_setup.sql -> 02_build_and_load.sql.
-- ============================================================

USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NorthwindDW')
BEGIN
    ALTER DATABASE NorthwindDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthwindDW;
    PRINT 'Banco NorthwindDW removido.';
END
ELSE
BEGIN
    PRINT 'NorthwindDW nao existia.';
END
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Northwind')
BEGIN
    ALTER DATABASE Northwind SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Northwind;
    PRINT 'Banco Northwind removido.';
END
ELSE
BEGIN
    PRINT 'Northwind nao existia.';
END
GO

PRINT 'Ambiente limpo.';
GO
