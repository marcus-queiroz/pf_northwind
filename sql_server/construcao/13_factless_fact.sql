-- =============================================================
-- 13_factless_fact.sql
-- Padrao: Factless Fact Table
-- Contexto: FactEmployeeTerritoryActivity registra EVENTOS
-- sem metricas: um empregado processou pedido(s) em um dia,
-- estando associado a determinados territorios via bridge.
-- Grain: (ActivityDateKey, EmployeeSK, TerritorySK) unico
-- =============================================================
-- DEPENDENCIA: 10_bridge_table.sql deve ter sido executado.

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

EXEC gold.sp_process_factless_activity;
GO

-- ---------------------------------------------------------------
-- DEMO 1: Territorios nunca cobertos por seus empregados
-- (pedidos existem mas nunca foram processados por emp. do territorio)
-- ---------------------------------------------------------------
PRINT '-- DEMO 1: Territorios sem cobertura real --';
SELECT
    dt.RegionName,
    dt.TerritoryDescription,
    de.FullName     AS EmpregadoResponsavel
FROM gold.BridgeEmployeeTerritory  b
JOIN gold.DimTerritory             dt ON dt.TerritorySK = b.TerritorySK
JOIN gold.DimEmployee              de ON de.EmployeeSK  = b.EmployeeSK
WHERE NOT EXISTS (
    SELECT 1
    FROM gold.FactEmployeeTerritoryActivity fa
    WHERE fa.EmployeeSK = b.EmployeeSK
      AND fa.TerritorySK = b.TerritorySK
)
ORDER BY dt.RegionName;
GO

-- ---------------------------------------------------------------
-- DEMO 2: Dias ativos por empregado x territorio
-- ---------------------------------------------------------------
PRINT '-- DEMO 2: Dias ativos por empregado e territorio --';
SELECT
    de.FullName,
    dt.TerritoryDescription,
    COUNT(*)  AS DiasComAtividade
FROM gold.FactEmployeeTerritoryActivity fa
JOIN gold.DimEmployee  de ON de.EmployeeSK  = fa.EmployeeSK
JOIN gold.DimTerritory dt ON dt.TerritorySK = fa.TerritorySK
GROUP BY de.FullName, dt.TerritoryDescription
ORDER BY DiasComAtividade DESC;
GO

-- ---------------------------------------------------------------
-- DEMO 3: Cobertura territorial por ano (densidade de cobertura)
-- ---------------------------------------------------------------
PRINT '-- DEMO 3: Cobertura territorial por ano --';
SELECT
    d.Year,
    dt.RegionName,
    COUNT(DISTINCT fa.TerritorySK)   AS TerritoriosCobertos,
    COUNT(DISTINCT fa.EmployeeSK)    AS EmpregadosAtivos,
    COUNT(*)                          AS TotalEventos
FROM gold.FactEmployeeTerritoryActivity fa
JOIN gold.DimDate                 d  ON d.DateKey     = fa.ActivityDateKey
JOIN gold.DimTerritory            dt ON dt.TerritorySK = fa.TerritorySK
GROUP BY d.Year, dt.RegionName
ORDER BY d.Year, dt.RegionName;
GO
