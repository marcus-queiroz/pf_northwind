-- ============================================================
-- 10_bridge_table_lab.sql
-- Lab: carrega a bridge Employee <-> Territory e explora consultas
-- que a bridge resolve (e o STRING_AGG de DimEmployee, nao).
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Carregar a bridge
EXEC gold.sp_process_bridge_employee_territory;
GO

-- ---------------------------------------------------------------
-- DEMO 1: Receita por territorio (via bridge, nao via string)
-- Sem a bridge, essa query seria impossivel de forma limpa.
-- ---------------------------------------------------------------
PRINT '-- DEMO 1: Receita por territorio via bridge --';
SELECT
    dt.RegionName,
    dt.TerritoryDescription,
    COUNT(DISTINCT fs.OrderID)          AS OrderCount,
    SUM(fs.NetRevenue)                  AS TotalRevenue
FROM gold.FactSales fs
JOIN gold.DimEmployee              de ON de.EmployeeSK  = fs.EmployeeSK
JOIN gold.BridgeEmployeeTerritory  b  ON b.EmployeeSK   = de.EmployeeSK
JOIN gold.DimTerritory             dt ON dt.TerritorySK = b.TerritorySK
GROUP BY dt.RegionName, dt.TerritoryDescription
ORDER BY TotalRevenue DESC;
GO

-- ---------------------------------------------------------------
-- DEMO 2: Territorios com empregados atribuidos mas sem pedidos
-- "O que nao aconteceu?" — essa e a forca da bridge.
-- ---------------------------------------------------------------
PRINT '-- DEMO 2: Territorios sem pedidos --';
SELECT
    dt.TerritoryDescription,
    dt.RegionName,
    de.FullName AS AssignedEmployee
FROM gold.BridgeEmployeeTerritory  b
JOIN gold.DimTerritory             dt ON dt.TerritorySK = b.TerritorySK
JOIN gold.DimEmployee              de ON de.EmployeeSK  = b.EmployeeSK
WHERE NOT EXISTS (
    SELECT 1
    FROM gold.FactSales fs
    WHERE fs.EmployeeSK = b.EmployeeSK
)
ORDER BY dt.RegionName, dt.TerritoryDescription;
GO

-- ---------------------------------------------------------------
-- DEMO 3: Empregado que cobre mais territorios distintos
-- ---------------------------------------------------------------
PRINT '-- DEMO 3: Cobertura territorial por empregado --';
SELECT
    de.FullName,
    COUNT(b.TerritorySK)   AS QuantidadeTerretorios,
    STRING_AGG(dt.TerritoryDescription, ', ')
        WITHIN GROUP (ORDER BY dt.TerritoryDescription)  AS Territorios
FROM gold.BridgeEmployeeTerritory b
JOIN gold.DimEmployee  de ON de.EmployeeSK  = b.EmployeeSK
JOIN gold.DimTerritory dt ON dt.TerritorySK = b.TerritorySK
GROUP BY de.FullName
ORDER BY QuantidadeTerretorios DESC;
GO
