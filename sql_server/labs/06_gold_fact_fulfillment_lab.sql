-- ============================================================
-- 06_gold_fact_fulfillment_lab.sql
-- Lab: demonstra o Accumulating Snapshot (FactOrderFulfillment)
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Carga inicial
EXEC gold.sp_process_fact_fulfillment;
GO

-- Verificar total (deve ter 830 linhas — um por pedido)
SELECT COUNT(*) AS TotalPedidos FROM gold.FactOrderFulfillment;
-- Esperado: 830
GO

-- PASSO 2: Pedidos pendentes (ShippedDate IS NULL no bronze)
SELECT TOP 5
    OrderID, OrderDateKey, RequiredDateKey,
    ShippedDateKey, DaysToShip, IsLate
FROM gold.FactOrderFulfillment
WHERE ShippedDateKey IS NULL
ORDER BY OrderID;
-- Esperado: ~21 pedidos com ShippedDateKey = NULL
GO

-- Contar pedidos pendentes vs entregues
SELECT
    SUM(CASE WHEN ShippedDateKey IS NULL THEN 1 ELSE 0 END) AS Pendentes,
    SUM(CASE WHEN ShippedDateKey IS NOT NULL THEN 1 ELSE 0 END) AS Entregues
FROM gold.FactOrderFulfillment;
-- Esperado: Pendentes = 21, Entregues = 809
GO

-- PASSO 3: Simular chegada de um envio
-- (pedido 11008 existe e nao foi enviado no Northwind original)
UPDATE bronze.Orders
SET ShippedDate = GETDATE()
WHERE OrderID = 11008 AND ShippedDate IS NULL;
GO

-- PASSO 4: Re-executar — deve atualizar a linha existente
EXEC gold.sp_process_fact_fulfillment;
GO

-- Verificar que a linha foi atualizada (nao duplicada)
SELECT OrderID, ShippedDateKey, DaysToShip, IsLate, LoadTimestamp
FROM gold.FactOrderFulfillment
WHERE OrderID = 11008;
-- Esperado: ShippedDateKey preenchido, DaysToShip >= 0, mesma linha (sem duplicata)
GO

-- Confirmar: ainda 830 linhas (nao houve INSERT novo)
SELECT COUNT(*) AS TotalPedidos, COUNT(DISTINCT OrderID) AS PedidosUnicos
FROM gold.FactOrderFulfillment;
-- Esperado: 830 e 830
GO

-- PASSO 5: Analise de SLA por Shipper
SELECT
    s.CompanyName                                                  AS Shipper,
    COUNT(*)                                                       AS TotalEntregues,
    SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)                 AS OnTime,
    SUM(CASE WHEN f.IsLate = 1 THEN 1 ELSE 0 END)                 AS Atrasados,
    CAST(100.0 * SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,1))                   AS OnTimePct,
    AVG(CAST(f.DaysToShip AS FLOAT))                              AS MediaDiasEnvio
FROM gold.FactOrderFulfillment f
JOIN gold.DimShipper s ON f.ShipperSK = s.ShipperSK
WHERE f.ShippedDateKey IS NOT NULL
GROUP BY s.CompanyName
ORDER BY OnTimePct DESC;
GO

-- Restaurar bronze para o estado original
UPDATE bronze.Orders SET ShippedDate = NULL WHERE OrderID = 11008;
GO
