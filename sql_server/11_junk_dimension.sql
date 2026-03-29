-- =============================================================
-- 11_junk_dimension.sql
-- Padrao: Junk Dimension
-- Contexto: DimOrderFlags agrupa atributos de baixa cardinalidade
-- que descrevem o contexto de cada linha de venda.
-- - DiscountBand: derivado do Discount real do Order Details
-- - IsHighValue: NetRevenue > 1000 (limiar de negocio)
-- - ShipmentMode: mapeado deterministicamente por ShipperID
--   (Northwind nao tem campo, mas o padrao e demonstrado)
-- =============================================================

USE NorthwindDW;
GO

-- Passo 1: Popular todas as 24 combinacoes possiveis (4x2x3)
TRUNCATE TABLE gold.DimOrderFlags;

WITH combos AS (
    SELECT d.DiscountBand, v.IsHighValue, s.ShipmentMode
    FROM (VALUES ('None'), ('Low'), ('Medium'), ('High')) AS d(DiscountBand)
    CROSS JOIN (VALUES (CAST(0 AS BIT)), (CAST(1 AS BIT))) AS v(IsHighValue)
    CROSS JOIN (VALUES ('Express'), ('Standard'), ('Economy')) AS s(ShipmentMode)
)
INSERT INTO gold.DimOrderFlags (DiscountBand, IsHighValue, ShipmentMode)
SELECT DiscountBand, IsHighValue, ShipmentMode FROM combos;
GO

-- Passo 2: Popular OrderFlagsSK no FactSales existente
UPDATE fs
SET fs.OrderFlagsSK = dof.OrderFlagsSK
FROM gold.FactSales fs
JOIN bronze.Orders o ON o.OrderID = fs.OrderID
JOIN gold.DimOrderFlags dof
    ON dof.DiscountBand = CASE
           WHEN fs.Discount = 0          THEN 'None'
           WHEN fs.Discount <= 0.05      THEN 'Low'
           WHEN fs.Discount <= 0.15      THEN 'Medium'
           ELSE                               'High'
       END
    AND dof.IsHighValue = CASE
           WHEN fs.NetRevenue > 1000     THEN CAST(1 AS BIT)
           ELSE                               CAST(0 AS BIT)
       END
    AND dof.ShipmentMode = CASE o.ShipVia
           WHEN 1 THEN 'Express'    -- Speedy Express
           WHEN 2 THEN 'Standard'   -- United Package
           ELSE        'Economy'    -- Federal Shipping
       END;
GO

PRINT 'FactSales.OrderFlagsSK populado: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas.';
GO

-- Passo 3: Procedure para carga incremental (novos pedidos)
CREATE OR ALTER PROCEDURE gold.sp_process_junk_dimension
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE fs
    SET fs.OrderFlagsSK = dof.OrderFlagsSK
    FROM gold.FactSales fs
    JOIN bronze.Orders o ON o.OrderID = fs.OrderID
    JOIN gold.DimOrderFlags dof
        ON dof.DiscountBand = CASE
               WHEN fs.Discount = 0          THEN 'None'
               WHEN fs.Discount <= 0.05      THEN 'Low'
               WHEN fs.Discount <= 0.15      THEN 'Medium'
               ELSE                               'High'
           END
        AND dof.IsHighValue = CASE
               WHEN fs.NetRevenue > 1000 THEN CAST(1 AS BIT)
               ELSE                           CAST(0 AS BIT)
           END
        AND dof.ShipmentMode = CASE o.ShipVia
               WHEN 1 THEN 'Express'
               WHEN 2 THEN 'Standard'
               ELSE        'Economy'
           END
    WHERE fs.OrderFlagsSK IS NULL;

    PRINT 'Junk dimension atualizada: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas.';
END;
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
