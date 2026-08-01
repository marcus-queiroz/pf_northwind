-- ============================================================
-- 03_silver_dims_lab.sql
-- Lab: processa dimensoes SCD1 e valida resultados
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Processar todas as dimensoes SCD1 + DimDate
EXEC gold.sp_process_dims;
GO

-- PASSO 2: Verificar contagens
SELECT 'DimEmployee'  AS Dimensao, COUNT(*) AS Linhas FROM gold.DimEmployee
UNION ALL
SELECT 'DimCategory',              COUNT(*) FROM gold.DimCategory
UNION ALL
SELECT 'DimSupplier',              COUNT(*) FROM gold.DimSupplier
UNION ALL
SELECT 'DimShipper',               COUNT(*) FROM gold.DimShipper
UNION ALL
SELECT 'DimTerritory',             COUNT(*) FROM gold.DimTerritory
UNION ALL
SELECT 'DimDate',                  COUNT(*) FROM gold.DimDate;
-- Esperado:
--   DimEmployee   9
--   DimCategory   8
--   DimSupplier  29
--   DimShipper    3
--   DimTerritory 53
--   DimDate   14975  (1990-01-01 a 2030-12-31)
GO

-- PASSO 3: DimEmployee com hierarquia achatada
SELECT
    EmployeeSK,
    FullName,
    Title,
    ManagerName,
    TerritoryList,
    RegionName
FROM gold.DimEmployee
ORDER BY ManagerName, FullName;
-- Observar: ManagerName = NULL para Andrew Fuller (presidente, nao tem gestor)
GO

-- PASSO 4: Verificar DimDate
-- Sample de datas importantes
SELECT * FROM gold.DimDate WHERE DateKey IN (19960701, 19971231, 20000101, 20300101);

-- Verificar fim de semana
SELECT TOP 5 FullDate, DayName, IsWeekend FROM gold.DimDate WHERE IsWeekend = 1;
GO

-- PASSO 5: Idempotencia — re-executar nao deve duplicar
EXEC gold.sp_process_dims;
GO
SELECT 'DimEmployee' AS Dimensao, COUNT(*) AS Linhas FROM gold.DimEmployee
UNION ALL SELECT 'DimCategory', COUNT(*) FROM gold.DimCategory
UNION ALL SELECT 'DimSupplier', COUNT(*) FROM gold.DimSupplier
UNION ALL SELECT 'DimShipper',  COUNT(*) FROM gold.DimShipper
UNION ALL SELECT 'DimTerritory',COUNT(*) FROM gold.DimTerritory;
-- Esperado: mesmos numeros que acima (sem duplicatas)
GO
