-- ============================================================
-- 05_gold_fact_sales.sql
-- Procedure: gold.sp_process_fact_sales
-- Tecnica: MERGE — evita duplicatas, join com dimensoes via natural key
-- Grain: uma linha por (OrderID, ProductID)
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_sales
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

    MERGE gold.FactSales AS tgt
    USING (
        SELECT
            -- DateKey
            CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)  AS OrderDateKey,
            -- Surrogate keys
            dc.CustomerSK,
            dp.ProductSK,
            de.EmployeeSK,
            ds.ShipperSK,
            -- Natural keys (para deduplicacao)
            od.OrderID,
            od.ProductID,
            -- Metricas
            od.UnitPrice,
            od.Quantity,
            CAST(od.Discount AS DECIMAL(5,4))             AS Discount,
            od.UnitPrice * od.Quantity                    AS GrossRevenue,
            CAST(
                od.UnitPrice * od.Quantity * (1.0 - od.Discount)
            AS DECIMAL(12,2))                             AS NetRevenue
        FROM bronze.OrderDetails od
        JOIN bronze.Orders o
            ON o.OrderID = od.OrderID
        -- CustomerSK: versao vigente na data do pedido
        JOIN gold.DimCustomer dc
            ON dc.CustomerID = o.CustomerID
           AND CAST(o.OrderDate AS DATE) >= dc.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dc.ValidTo
        -- ProductSK: versao vigente na data do pedido
        JOIN gold.DimProduct dp
            ON dp.ProductID = od.ProductID
           AND CAST(o.OrderDate AS DATE) >= dp.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dp.ValidTo
        JOIN gold.DimEmployee de
            ON de.EmployeeID = o.EmployeeID
        JOIN gold.DimShipper ds
            ON ds.ShipperID = o.ShipVia
    ) AS src 
		ON tgt.OrderID = src.OrderID AND tgt.ProductID = src.ProductID

    WHEN MATCHED THEN UPDATE SET
        tgt.OrderDateKey  = src.OrderDateKey,
        tgt.CustomerSK    = src.CustomerSK,
        tgt.ProductSK     = src.ProductSK,
        tgt.EmployeeSK    = src.EmployeeSK,
        tgt.ShipperSK     = src.ShipperSK,
        tgt.UnitPrice     = src.UnitPrice,
        tgt.Quantity      = src.Quantity,
        tgt.Discount      = src.Discount,
        tgt.GrossRevenue  = src.GrossRevenue,
        tgt.NetRevenue    = src.NetRevenue,
        tgt.LoadTimestamp = GETDATE()

    WHEN NOT MATCHED BY TARGET THEN INSERT (
        OrderDateKey, CustomerSK, ProductSK, EmployeeSK, ShipperSK,
        OrderID, ProductID,
        UnitPrice, Quantity, Discount, GrossRevenue, NetRevenue, LoadTimestamp
    ) VALUES (
        src.OrderDateKey, src.CustomerSK, src.ProductSK, src.EmployeeSK, src.ShipperSK,
        src.OrderID, src.ProductID,
        src.UnitPrice, src.Quantity, src.Discount, src.GrossRevenue, src.NetRevenue,
        GETDATE()
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactSales', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactSales', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO
