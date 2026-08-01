-- ============================================================
-- 13_factless_fact_lab.sql
-- Lab: carrega FactEmployeeTerritoryActivity e explora perguntas
-- de cobertura que um fato sem metricas responde.
-- DEPENDENCIA: rode 10_bridge_table_lab.sql antes (BridgeEmployeeTerritory).
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Carregar os eventos de atividade
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
