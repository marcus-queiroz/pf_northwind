-- ============================================================
-- 02_bronze_ingest_lab.sql
-- Lab: executa a ingestao bronze e valida os resultados
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Executar ingestao
EXEC bronze.sp_ingest_bronze;
GO

-- PASSO 2: Verificar log de execucao
SELECT StepName, RowsAffected, Status, EndTime
FROM control.pipeline_log
ORDER BY LogID;
GO

-- PASSO 3: Comparativo de contagens dbo vs bronze
SELECT
    'Customers'      AS Tabela,
    (SELECT COUNT(*) FROM Northwind.dbo.Customers)    AS LinhasDBO,
    (SELECT COUNT(*) FROM bronze.Customers)           AS LinhasBronze
UNION ALL SELECT
    'Employees',
    (SELECT COUNT(*) FROM Northwind.dbo.Employees),
    (SELECT COUNT(*) FROM bronze.Employees)
UNION ALL SELECT
    'Products',
    (SELECT COUNT(*) FROM Northwind.dbo.Products),
    (SELECT COUNT(*) FROM bronze.Products)
UNION ALL SELECT
    'Categories',
    (SELECT COUNT(*) FROM Northwind.dbo.Categories),
    (SELECT COUNT(*) FROM bronze.Categories)
UNION ALL SELECT
    'Suppliers',
    (SELECT COUNT(*) FROM Northwind.dbo.Suppliers),
    (SELECT COUNT(*) FROM bronze.Suppliers)
UNION ALL SELECT
    'Shippers',
    (SELECT COUNT(*) FROM Northwind.dbo.Shippers),
    (SELECT COUNT(*) FROM bronze.Shippers)
UNION ALL SELECT
    'Orders',
    (SELECT COUNT(*) FROM Northwind.dbo.Orders),
    (SELECT COUNT(*) FROM bronze.Orders)
UNION ALL SELECT
    'OrderDetails',
    (SELECT COUNT(*) FROM Northwind.dbo.[Order Details]),
    (SELECT COUNT(*) FROM bronze.OrderDetails)
UNION ALL SELECT
    'Territories',
    (SELECT COUNT(*) FROM Northwind.dbo.Territories),
    (SELECT COUNT(*) FROM bronze.Territories)
UNION ALL SELECT
    'Region',
    (SELECT COUNT(*) FROM Northwind.dbo.Region),
    (SELECT COUNT(*) FROM bronze.Region)
UNION ALL SELECT
    'EmployeeTerritories',
    (SELECT COUNT(*) FROM Northwind.dbo.EmployeeTerritories),
    (SELECT COUNT(*) FROM bronze.EmployeeTerritories);
-- Esperado: LinhasDBO = LinhasBronze em todas as linhas

-- PASSO 4: Amostra de cada tabela bronze
SELECT TOP 3 * FROM bronze.Customers;
SELECT TOP 3 * FROM bronze.Employees;
SELECT TOP 3 * FROM bronze.Products;
SELECT TOP 3 * FROM bronze.Orders;
SELECT TOP 3 * FROM bronze.OrderDetails;
GO

-- PASSO 5: Verificar que _LoadTimestamp foi preenchido automaticamente
SELECT
    MIN(_LoadTimestamp) AS PrimeiraCarga,
    MAX(_LoadTimestamp) AS UltimaCarga,
    COUNT(*)            AS TotalLinhas
FROM bronze.Customers;
GO
