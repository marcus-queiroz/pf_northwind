-- ============================================================
-- 05_gold_fact_sales_lab.sql
-- Lab: carrega FactSales e valida
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Carregar FactSales
EXEC gold.sp_process_fact_sales;
GO

-- PASSO 2: Contagem
SELECT COUNT(*) AS TotalLinhas FROM gold.FactSales;
-- Esperado: 2155 (= COUNT de bronze.OrderDetails)
GO

-- PASSO 3: Reconciliacao — SUM(NetRevenue) no fato vs calculo direto no bronze
SELECT
    (SELECT SUM(CAST(UnitPrice * Quantity * (1.0 - Discount) AS DECIMAL(12,2)))
     FROM bronze.OrderDetails)     AS NetRevenueBronze,
    (SELECT SUM(NetRevenue)
     FROM gold.FactSales)          AS NetRevenueFato;
-- Esperado: valores iguais (ou diferenca < $0.01 por arredondamento de REAL)
GO

-- PASSO 4: GrossRevenue sempre >= NetRevenue (desconto nao pode ser negativo)
SELECT MIN(GrossRevenue - NetRevenue) AS MinDiferenca FROM gold.FactSales;
-- Esperado: >= 0
GO

-- PASSO 5: Integridade referencial — chaves da fato existem nas dimensoes
-- LEFT JOIN + WHERE IS NULL detecta linhas na fato cujo SK nao tem par na dimensao.
-- Se o MERGE da procedure estiver correto, isso nunca ocorre — mas vale validar.

-- CustomerSK: todo cliente referenciado na fato existe em DimCustomer?
SELECT COUNT(*) AS OrfaosCustomer
FROM gold.FactSales f
LEFT JOIN gold.DimCustomer c ON f.CustomerSK = c.CustomerSK
WHERE c.CustomerSK IS NULL;
-- Esperado: 0

-- ProductSK: todo produto referenciado na fato existe em DimProduct?
SELECT COUNT(*) AS OrfaosProduto
FROM gold.FactSales f
LEFT JOIN gold.DimProduct p ON f.ProductSK = p.ProductSK
WHERE p.ProductSK IS NULL;
-- Esperado: 0

-- OrderDateKey: toda data de pedido existe em DimDate (serie 1990-2030)?
SELECT COUNT(*) AS OrfaosData
FROM gold.FactSales f
LEFT JOIN gold.DimDate d ON f.OrderDateKey = d.DateKey
WHERE d.DateKey IS NULL;
-- Esperado: 0
GO

-- PASSO 6: Top 5 pedidos por NetRevenue
SELECT TOP 5
    f.OrderID,
    c.CompanyName    AS Cliente,
    p.ProductName    AS Produto,
    f.Quantity,
    f.Discount,
    f.GrossRevenue,
    f.NetRevenue
FROM gold.FactSales f
JOIN gold.DimCustomer c ON f.CustomerSK = c.CustomerSK
JOIN gold.DimProduct  p ON f.ProductSK  = p.ProductSK
ORDER BY f.NetRevenue DESC;
GO

-- PASSO 7: Idempotencia — re-executar nao duplica
EXEC gold.sp_process_fact_sales;
GO
SELECT COUNT(*) AS TotalLinhas FROM gold.FactSales;
-- Esperado: ainda 2155
GO
