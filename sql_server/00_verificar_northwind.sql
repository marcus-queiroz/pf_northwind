-- ============================================================
-- 00_verificar_northwind.sql
-- Verifica se o banco Northwind existe com os dados carregados.
--
-- Pre-requisito: Northwind ja criado via course_northwind.
-- Se ainda nao existir, execute primeiro:
--   course_northwind/setup/00_criar_northwind.sql  (cria banco + schema curso)
--   instnwnd.sql                                   (carrega dados dbo.*)
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Northwind')
BEGIN
    PRINT 'ERRO: Banco Northwind nao encontrado.';
    PRINT 'Execute primeiro: course_northwind/setup/00_criar_northwind.sql';
    RETURN;
END
GO

USE Northwind;
GO

-- Verificar se os dados estao carregados
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo') AND name = 'Customers')
BEGIN
    PRINT 'ERRO: Tabelas dbo.* nao encontradas.';
    PRINT 'Execute instnwnd.sql para carregar os dados do Northwind.';
    RETURN;
END
GO

-- Contagem de linhas das tabelas utilizadas no DW
SELECT 'Customers'           AS Tabela, COUNT(*) AS Linhas FROM dbo.Customers
UNION ALL
SELECT 'Employees',                     COUNT(*) FROM dbo.Employees
UNION ALL
SELECT 'Products',                      COUNT(*) FROM dbo.Products
UNION ALL
SELECT 'Categories',                    COUNT(*) FROM dbo.Categories
UNION ALL
SELECT 'Suppliers',                     COUNT(*) FROM dbo.Suppliers
UNION ALL
SELECT 'Shippers',                      COUNT(*) FROM dbo.Shippers
UNION ALL
SELECT 'Orders',                        COUNT(*) FROM dbo.Orders
UNION ALL
SELECT 'Order Details',                 COUNT(*) FROM dbo.[Order Details]
UNION ALL
SELECT 'Territories',                   COUNT(*) FROM dbo.Territories
UNION ALL
SELECT 'Region',                        COUNT(*) FROM dbo.Region
UNION ALL
SELECT 'EmployeeTerritories',           COUNT(*) FROM dbo.EmployeeTerritories
ORDER BY Tabela;

-- Esperado:
--   Categories           8
--   Customers           91
--   EmployeeTerritories 49
--   Employees            9
--   Order Details     2155
--   Orders             830
--   Products            77
--   Region               4
--   Shippers             3
--   Suppliers           29
--   Territories         53

-- Pedidos sem ShippedDate (ficam pendentes no Accumulating Snapshot)
SELECT COUNT(*) AS PedidosPendentes
FROM dbo.Orders
WHERE ShippedDate IS NULL;
-- Esperado: 21
GO
