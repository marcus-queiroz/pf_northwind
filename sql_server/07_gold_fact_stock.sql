-- ============================================================
-- 07_gold_fact_stock.sql
-- Procedure: gold.sp_process_fact_stock
-- Tecnica: Periodic Snapshot — INSERT do estado atual de Products
-- Cada execucao adiciona uma nova linha por produto (nao faz UPDATE)
-- Grain: (ProductSK, SnapshotDateKey)
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_stock
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @snapshotDateKey INT =
        CAST(FORMAT(GETDATE(), 'yyyyMMdd') AS INT);

    -- Nao inserir se ja existe snapshot de hoje
    IF EXISTS (
        SELECT 1 FROM gold.FactProductStock
        WHERE SnapshotDateKey = @snapshotDateKey
    )
    BEGIN
        PRINT 'Snapshot de hoje (' + CAST(@snapshotDateKey AS VARCHAR) + ') ja existe. Nenhuma acao.';
        RETURN;
    END;

    BEGIN TRY

    INSERT INTO gold.FactProductStock
        (SnapshotDateKey, ProductSK, CategorySK,
         UnitsInStock, UnitsOnOrder, ReorderLevel, NeedsReorder, LoadTimestamp)
    SELECT
        @snapshotDateKey,
        dp.ProductSK,
        dc.CategorySK,
        p.UnitsInStock,
        p.UnitsOnOrder,
        p.ReorderLevel,
        CASE WHEN p.UnitsInStock <= p.ReorderLevel THEN 1 ELSE 0 END AS NeedsReorder,
        GETDATE()
    FROM bronze.Products p
    JOIN gold.DimProduct dp
        ON dp.ProductID = p.ProductID AND dp.IsCurrent = 1
    JOIN gold.DimCategory dc
        ON dc.CategoryID = p.CategoryID;

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactProductStock', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactProductStock', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO
