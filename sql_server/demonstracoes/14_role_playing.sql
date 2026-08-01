-- =============================================================
-- 14_role_playing.sql
-- Padrao: Role-Playing Dimension
-- Contexto: DimDate e referenciada 3x no FactOrderFulfillment
-- com papeis distintos. Views com nomes semanticos tornam as
-- queries mais legiveis e documentam o padrao explicitamente.
--
-- Padrao: Degenerate Dimension
-- Contexto: OrderID em FactSales nao tem dimensao propria
-- (sem atributos descritivos), mas e mantido no fato para
-- drill-through e rastreabilidade. E uma "dimensao degenerada".
-- =============================================================

USE NorthwindDW;
GO

-- As views ja foram criadas em 01_setup.sql.
-- Este arquivo documenta o padrao e demonstra com queries.

-- ---------------------------------------------------------------
-- DEMO ROLE-PLAYING: join com 3 aliases do mesmo DimDate
-- Cada view e um "papel" semantico da mesma dimensao fisica.
-- ---------------------------------------------------------------
PRINT '-- DEMO: Role-Playing Dimension — pedidos por ano/trimestre --';
SELECT
    od.Year                             AS AnoDosPedidos,
    od.Quarter                          AS Trimestre,
    COUNT(DISTINCT f.OrderID)           AS TotalPedidos,
    COUNT(f.ShippedDateKey)             AS PedidosEnviados,
    SUM(CASE WHEN f.ShippedDateKey IS NULL
             THEN 1 ELSE 0 END)         AS PedidosPendentes,
    AVG(CAST(f.DaysToShip AS FLOAT))    AS MediaDiasEnvio,
    SUM(CASE WHEN f.IsLate = 1
             THEN 1 ELSE 0 END)         AS EnviosAtrasados
FROM gold.FactOrderFulfillment     f
JOIN gold.v_OrderDate    od ON od.DateKey = f.OrderDateKey
LEFT JOIN gold.v_ShippedDate  sd ON sd.DateKey = f.ShippedDateKey
LEFT JOIN gold.v_RequiredDate rd ON rd.DateKey = f.RequiredDateKey
GROUP BY od.Year, od.Quarter
ORDER BY od.Year, od.Quarter;
GO

-- ---------------------------------------------------------------
-- DEMO ROLE-PLAYING: sazonalidade de pedidos vs envios
-- Mes em que o pedido foi feito vs mes em que foi enviado
-- ---------------------------------------------------------------
PRINT '-- DEMO: Sazonalidade pedido vs envio --';
SELECT
    od.MonthName  AS MesPedido,
    sd.MonthName  AS MesEnvio,
    COUNT(*)      AS Pedidos,
    AVG(f.DaysToShip) AS MediaDias
FROM gold.FactOrderFulfillment f
JOIN gold.v_OrderDate    od ON od.DateKey = f.OrderDateKey
JOIN gold.v_ShippedDate  sd ON sd.DateKey = f.ShippedDateKey
GROUP BY od.Month, od.MonthName, sd.Month, sd.MonthName
ORDER BY od.Month, sd.Month;
GO

-- ---------------------------------------------------------------
-- DEGENERATE DIMENSION: OrderID em FactSales
-- OrderID nao tem DimOrder — ele e a propria chave degenerada.
-- Permite drill-through: "quais itens compoem o pedido X?"
-- ---------------------------------------------------------------

-- DEMO: Drill-through de um pedido especifico via OrderID (DD)
PRINT '-- DEMO: Degenerate Dimension — drill-through pedido 10248 --';
DECLARE @OrderID INT = 10248;

SELECT
    fs.OrderID,             -- Degenerate Dimension
    dc.CompanyName,
    dp.ProductName,
    fs.Quantity,
    fs.UnitPrice,
    fs.Discount,
    fs.NetRevenue
FROM gold.FactSales fs
JOIN gold.DimCustomer dc ON dc.CustomerSK = fs.CustomerSK AND dc.IsCurrent = 1
JOIN gold.DimProduct  dp ON dp.ProductSK  = fs.ProductSK  AND dp.IsCurrent = 1
WHERE fs.OrderID = @OrderID;
GO

-- DEMO: Comparar pedidos do mesmo cliente — usando DD como agrupador
PRINT '-- DEMO: Degenerate Dimension — pedidos por cliente --';
SELECT
    fs.OrderID,             -- Degenerate Dimension como agrupador
    MIN(d.FullDate)         AS DataPedido,
    SUM(fs.NetRevenue)      AS TotalPedido,
    COUNT(*)                AS Itens
FROM gold.FactSales fs
JOIN gold.DimCustomer dc ON dc.CustomerSK = fs.CustomerSK AND dc.IsCurrent = 1
JOIN gold.DimDate      d  ON d.DateKey    = fs.OrderDateKey
WHERE dc.CompanyName = 'Alfreds Futterkiste'
GROUP BY fs.OrderID
ORDER BY DataPedido;
GO
