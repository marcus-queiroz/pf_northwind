-- ============================================================
-- 04_silver_scd2_lab.sql
-- Lab: demonstra o padrao SCD Tipo 2
-- ============================================================

USE NorthwindDW;
GO

-- ============================================================
-- PARTE A — DimCustomer SCD2
-- ============================================================

-- PASSO 1: Carga inicial
EXEC gold.sp_process_customers_scd2;
GO

-- Verificar: todos IsCurrent = 1, ValidFrom = 1900-01-01
SELECT
    COUNT(*)										AS TotalLinhas,
    SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END)	AS TotalCurrent,
    MIN(ValidFrom)									AS ValidFromMin,
    MAX(ValidTo)									AS ValidToMax
FROM gold.DimCustomer;
-- Esperado: TotalLinhas = 91, TotalCurrent = 91, ValidFrom = 1900-01-01
GO

-- PASSO 2: Simular mudanca de cidade para o cliente ALFKI
UPDATE bronze.Customers
SET City = 'Munique'     -- era 'Berlin'
WHERE CustomerID = 'ALFKI';
GO

-- PASSO 3: Re-executar — deve criar nova versao e expirar a anterior
EXEC gold.sp_process_customers_scd2;
GO

-- Verificar versoes do cliente ALFKI
SELECT CustomerID, CompanyName, City, ValidFrom, ValidTo, IsCurrent
FROM gold.DimCustomer
WHERE CustomerID = 'ALFKI'
ORDER BY ValidFrom;
-- Esperado: 2 linhas
--   Linha 1: City = 'Berlin',  IsCurrent = 0, ValidTo = hoje - 1
--   Linha 2: City = 'Munique', IsCurrent = 1, ValidTo = 9999-12-31
GO

-- PASSO 4: Confirmar que so um IsCurrent = 1 por CustomerID
SELECT CustomerID, COUNT(*) AS cnt
FROM gold.DimCustomer
WHERE IsCurrent = 1
GROUP BY CustomerID
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas (nenhum duplicado)
GO

-- PASSO 5: Total de linhas agora > 91 (versao antiga + nova de ALFKI)
SELECT COUNT(*) AS TotalLinhas FROM gold.DimCustomer;
-- Esperado: 92
GO

-- Restaurar bronze para o valor original
UPDATE bronze.Customers SET City = 'Berlin' WHERE CustomerID = 'ALFKI';
GO

-- ============================================================
-- PARTE B — DimProduct SCD2
-- ============================================================

-- PASSO 6: Carga inicial de produtos
EXEC gold.sp_process_products_scd2;
GO

-- Verificar carga
SELECT
    COUNT(*)                                       AS TotalLinhas,
    SUM(CASE WHEN IsCurrent = 1 THEN 1 ELSE 0 END) AS TotalCurrent,
    MIN(ValidFrom)                                 AS ValidFromMin
FROM gold.DimProduct;
-- Esperado: 77 linhas, 77 TotalCurrent, ValidFrom = 1900-01-01
GO

-- PASSO 7: Simular alteracao de preco do produto 1 (Chai)
UPDATE bronze.Products
SET UnitPrice = 99.99    -- era 18.00
WHERE ProductID = 1;
GO

-- PASSO 8: Re-executar SCD2 de produtos
EXEC gold.sp_process_products_scd2;
GO

-- Verificar historico de versoes do produto 1
SELECT ProductID, ProductName, UnitPrice, ValidFrom, ValidTo, IsCurrent
FROM gold.DimProduct
WHERE ProductID = 1
ORDER BY ValidFrom;
-- Esperado: 2 linhas
--   Linha 1: UnitPrice = 18.00, IsCurrent = 0
--   Linha 2: UnitPrice = 99.99, IsCurrent = 1
GO

-- Restaurar
UPDATE bronze.Products SET UnitPrice = 18.00 WHERE ProductID = 1;
GO

-- PASSO 9: Validar — nenhum ProductID com mais de 1 IsCurrent = 1
SELECT ProductID, COUNT(*) AS cnt
FROM gold.DimProduct
WHERE IsCurrent = 1
GROUP BY ProductID
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas
GO
