-- ============================================================
-- 11_junk_dimension_lab.sql
-- Lab: explora a Junk Dimension (DimOrderFlags) ja carregada.
-- DEPENDENCIA: construcao/11_junk_dimension.sql ja executa a
-- carga sozinho (nao ha procedure a chamar aqui antes de explorar).
-- ============================================================

USE NorthwindDW;
GO

-- ---------------------------------------------------------------
-- DEMO 1: Distribuicao de vendas por banda de desconto e modo de envio
-- ---------------------------------------------------------------
PRINT '-- DEMO 1: Vendas por DiscountBand e ShipmentMode --';
SELECT
    dof.DiscountBand,
    dof.ShipmentMode,
    COUNT(*)               AS Transacoes,
    SUM(fs.GrossRevenue)   AS GrossRevenue,
    SUM(fs.NetRevenue)     AS NetRevenue,
    SUM(fs.GrossRevenue) - SUM(fs.NetRevenue) AS DescontoTotal
FROM gold.FactSales fs
JOIN gold.DimOrderFlags dof ON dof.OrderFlagsSK = fs.OrderFlagsSK
GROUP BY dof.DiscountBand, dof.ShipmentMode
ORDER BY dof.DiscountBand, dof.ShipmentMode;
GO

-- ---------------------------------------------------------------
-- DEMO 2: High-value orders por modo de envio
-- ---------------------------------------------------------------
PRINT '-- DEMO 2: High-value orders por modo de envio --';
SELECT
    dof.ShipmentMode,
    dof.IsHighValue,
    COUNT(*)             AS Transacoes,
    AVG(fs.NetRevenue)   AS TicketMedio
FROM gold.FactSales fs
JOIN gold.DimOrderFlags dof ON dof.OrderFlagsSK = fs.OrderFlagsSK
GROUP BY dof.ShipmentMode, dof.IsHighValue
ORDER BY dof.ShipmentMode, dof.IsHighValue DESC;
GO
