-- =============================================================
-- 13_factless_fact.sql
-- Padrao: Factless Fact Table
-- Contexto: FactEmployeeTerritoryActivity registra EVENTOS
-- sem metricas: um empregado processou pedido(s) em um dia,
-- estando associado a determinados territorios via bridge.
-- Grain: (ActivityDateKey, EmployeeSK, TerritorySK) unico
--
-- So define a procedure. Execucao e exploracao:
-- sql_server/labs/13_factless_fact_lab.sql
-- =============================================================
-- DEPENDENCIA: a procedure de 10_bridge_table.sql precisa ja ter
-- sido executada (gold.BridgeEmployeeTerritory populada).

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_factless_activity
AS
BEGIN
    SET NOCOUNT ON;

    -- Carga full (idempotente via MERGE)
    MERGE gold.FactEmployeeTerritoryActivity AS tgt
    USING (
        SELECT DISTINCT
            CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)  AS ActivityDateKey,
            de.EmployeeSK,
            b.TerritorySK
        FROM bronze.Orders o
        JOIN gold.DimEmployee              de ON de.EmployeeID = o.EmployeeID
        JOIN gold.BridgeEmployeeTerritory  b  ON b.EmployeeSK = de.EmployeeSK
        JOIN gold.DimDate                  dd ON dd.DateKey    =
             CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)
    ) AS src
    ON  tgt.ActivityDateKey = src.ActivityDateKey
    AND tgt.EmployeeSK      = src.EmployeeSK
    AND tgt.TerritorySK     = src.TerritorySK
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ActivityDateKey, EmployeeSK, TerritorySK)
        VALUES (src.ActivityDateKey, src.EmployeeSK, src.TerritorySK);

    PRINT 'FactEmployeeTerritoryActivity: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas inseridas.';
END;
GO
