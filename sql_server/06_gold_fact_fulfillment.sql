-- ============================================================
-- 06_gold_fact_fulfillment.sql
-- Procedure: gold.sp_process_fact_fulfillment
-- Tecnica: Accumulating Snapshot — MERGE que:
--   INSERT novos pedidos
--   UPDATE pedidos existentes quando ShippedDate chega
-- Grain: uma linha por OrderID
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_fulfillment
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

    MERGE gold.FactOrderFulfillment AS tgt
    USING (
        SELECT
            o.OrderID,
            -- CustomerSK: versao vigente na data do pedido
            dc.CustomerSK,
            de.EmployeeSK,
            -- ShipperSK pode ser NULL se ShipVia for NULL
            ds.ShipperSK,
            -- DateKeys: converter datetime -> INT YYYYMMDD
            CAST(FORMAT(o.OrderDate,    'yyyyMMdd') AS INT) AS OrderDateKey,
            CAST(FORMAT(o.RequiredDate, 'yyyyMMdd') AS INT) AS RequiredDateKey,
            -- ShippedDateKey: NULL se ainda nao enviado
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN CAST(FORMAT(o.ShippedDate, 'yyyyMMdd') AS INT)
                 ELSE NULL END                              AS ShippedDateKey,
            o.Freight,
            o.ShipCountry,
            -- DaysToShip: NULL ate envio
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN DATEDIFF(day, o.OrderDate, o.ShippedDate)
                 ELSE NULL END                              AS DaysToShip,
            -- IsLate: NULL ate envio; 1 se atrasou, 0 se no prazo
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END
                 ELSE NULL END                              AS IsLate
        FROM bronze.Orders o
        -- CustomerSK: versao valida na data do pedido
        JOIN gold.DimCustomer dc
            ON dc.CustomerID = o.CustomerID
           AND CAST(o.OrderDate AS DATE) >= dc.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dc.ValidTo
        JOIN gold.DimEmployee de
            ON de.EmployeeID = o.EmployeeID
        LEFT JOIN gold.DimShipper ds
            ON ds.ShipperID = o.ShipVia
    ) AS src ON tgt.OrderID = src.OrderID

    -- Pedido ja existe: atualizar apenas se ShippedDate chegou ou mudou
    WHEN MATCHED AND (
        -- Comparacao NULL-safe compativel com SQL Server 2017+
        -- ISNULL(col, sentinela) garante que NULL = NULL nao dispara UPDATE
        ISNULL(tgt.ShippedDateKey, -1)      <> ISNULL(src.ShippedDateKey, -1) OR
        ISNULL(tgt.DaysToShip, -999)        <> ISNULL(src.DaysToShip, -999)   OR
        ISNULL(CAST(tgt.IsLate AS INT), -1) <> ISNULL(CAST(src.IsLate AS INT), -1)
    ) THEN UPDATE SET
        tgt.ShippedDateKey = src.ShippedDateKey,
        tgt.DaysToShip     = src.DaysToShip,
        tgt.IsLate         = src.IsLate,
        tgt.LoadTimestamp  = GETDATE()

    -- Pedido novo: inserir
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        OrderID, CustomerSK, EmployeeSK, ShipperSK,
        OrderDateKey, RequiredDateKey, ShippedDateKey,
        Freight, ShipCountry, DaysToShip, IsLate, LoadTimestamp
    ) VALUES (
        src.OrderID, src.CustomerSK, src.EmployeeSK, src.ShipperSK,
        src.OrderDateKey, src.RequiredDateKey, src.ShippedDateKey,
        src.Freight, src.ShipCountry, src.DaysToShip, src.IsLate,
        GETDATE()
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactOrderFulfillment', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactOrderFulfillment', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

