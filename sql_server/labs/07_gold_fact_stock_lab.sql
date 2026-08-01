-- ============================================================
-- 07_gold_fact_stock_lab.sql
-- Lab: demonstra o Periodic Snapshot (FactProductStock)
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Primeira execucao — captura snapshot de hoje
EXEC gold.sp_process_fact_stock;
GO

-- Verificar contagem
SELECT SnapshotDateKey, COUNT(*) AS Produtos
FROM gold.FactProductStock
GROUP BY SnapshotDateKey;
-- Esperado: 1 data (hoje), 77 produtos
GO

-- PASSO 2: Re-executar — nao duplica (guarda de data)
EXEC gold.sp_process_fact_stock;
GO

SELECT SnapshotDateKey, COUNT(*) AS Produtos
FROM gold.FactProductStock
GROUP BY SnapshotDateKey;
-- Esperado: ainda 1 data, 77 produtos
GO

-- PASSO 3: Produtos com necessidade de reposicao (NeedsReorder = 1)
SELECT
    p.ProductName,
    p.CategoryName,
    fs.UnitsInStock,
    fs.ReorderLevel,
    fs.UnitsOnOrder,
    fs.UnitsInStock - fs.ReorderLevel AS EstoqueAcimaReorder
FROM gold.FactProductStock fs
JOIN gold.DimProduct p ON fs.ProductSK = p.ProductSK
WHERE fs.NeedsReorder = 1
  AND fs.SnapshotDateKey = (SELECT MAX(SnapshotDateKey) FROM gold.FactProductStock)
ORDER BY EstoqueAcimaReorder;
GO

-- PASSO 4: Simular uma segunda execucao em "data diferente"
-- Inserir diretamente com data anterior para demonstrar a serie temporal
INSERT INTO gold.FactProductStock
    (SnapshotDateKey, ProductSK, CategorySK,
     UnitsInStock, UnitsOnOrder, ReorderLevel, NeedsReorder, LoadTimestamp)
SELECT
    19970101,   -- data simulada no passado
    dp.ProductSK,
    dc.CategorySK,
    -- Simular estoque diferente: dobrar UnitsInStock
    p.UnitsInStock * 2,
    p.UnitsOnOrder,
    p.ReorderLevel,
    CASE WHEN (p.UnitsInStock * 2) <= p.ReorderLevel THEN 1 ELSE 0 END,
    GETDATE()
FROM bronze.Products p
JOIN gold.DimProduct  dp ON dp.ProductID = p.ProductID AND dp.IsCurrent = 1
JOIN gold.DimCategory dc ON dc.CategoryID = p.CategoryID;
GO

-- PASSO 5: Comparar snapshots
SELECT
    SnapshotDateKey,
    COUNT(*)                                         AS Produtos,
    SUM(CAST(UnitsInStock AS INT))                   AS TotalEstoque,
    SUM(CASE WHEN NeedsReorder = 1 THEN 1 ELSE 0 END) AS PrecisaReposicao
FROM gold.FactProductStock
GROUP BY SnapshotDateKey
ORDER BY SnapshotDateKey;
-- Esperado: 2 datas — 19970101 (estoque maior) e hoje
GO

-- Limpar snapshot simulado
DELETE FROM gold.FactProductStock WHERE SnapshotDateKey = 19970101;
GO
