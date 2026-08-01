-- ============================================================
-- 09_validation.sql
-- 24 verificacoes de qualidade do NorthwindDW
-- Cada verificacao imprime resultado e esperado
-- ============================================================

USE NorthwindDW;
GO

PRINT '=== VALIDACOES NorthwindDW ===';
PRINT '';

-- ============================================================
-- 0.1 Fonte: dbo.Customers tem a contagem esperada
-- ============================================================
PRINT '-- 0.1. Fonte: dbo.Customers --';
SELECT COUNT(*) AS Linhas FROM Northwind.dbo.Customers;
-- Esperado: 91

-- ============================================================
-- 0.2 Fonte: dbo.Orders tem a contagem esperada
-- ============================================================
PRINT '-- 0.2. Fonte: dbo.Orders --';
SELECT COUNT(*) AS Linhas FROM Northwind.dbo.Orders;
-- Esperado: 830

-- ============================================================
-- 0.3 Fonte: dbo.[Order Details] tem a contagem esperada
-- ============================================================
PRINT '-- 0.3. Fonte: dbo.[Order Details] --';
SELECT COUNT(*) AS Linhas FROM Northwind.dbo.[Order Details];
-- Esperado: 2155

-- ============================================================
-- 0.4 Fonte: pedidos pendentes (sem ShippedDate)
-- ============================================================
PRINT '-- 0.4. Fonte: pedidos pendentes (sem ShippedDate) --';
SELECT COUNT(*) AS PedidosPendentes
FROM Northwind.dbo.Orders
WHERE ShippedDate IS NULL;
-- Esperado: 21

-- ============================================================
-- 1. Bronze = dbo: linhas identicas em todas as tabelas
-- ============================================================
PRINT '-- 1. Reconciliacao bronze vs dbo --';
SELECT
    Tabela,
    LinhasDBO,
    LinhasBronze,
    CASE WHEN LinhasDBO = LinhasBronze THEN 'OK' ELSE 'FALHA' END AS Status
FROM (
    SELECT 'Customers'          AS Tabela,
        (SELECT COUNT(*) FROM Northwind.dbo.Customers)        AS LinhasDBO,
        (SELECT COUNT(*) FROM bronze.Customers)               AS LinhasBronze
    UNION ALL SELECT 'Employees',
        (SELECT COUNT(*) FROM Northwind.dbo.Employees),
        (SELECT COUNT(*) FROM bronze.Employees)
    UNION ALL SELECT 'Products',
        (SELECT COUNT(*) FROM Northwind.dbo.Products),
        (SELECT COUNT(*) FROM bronze.Products)
    UNION ALL SELECT 'Orders',
        (SELECT COUNT(*) FROM Northwind.dbo.Orders),
        (SELECT COUNT(*) FROM bronze.Orders)
    UNION ALL SELECT 'OrderDetails',
        (SELECT COUNT(*) FROM Northwind.dbo.[Order Details]),
        (SELECT COUNT(*) FROM bronze.OrderDetails)
) x;
-- Esperado: Status = OK em todas as linhas
GO

-- ============================================================
-- 2. DimCustomer: sem duplicata de IsCurrent=1 por CustomerID
-- ============================================================
PRINT '-- 2. DimCustomer: sem duplicata IsCurrent=1 --';
SELECT CustomerID, COUNT(*) AS cnt
FROM gold.DimCustomer
WHERE IsCurrent = 1
GROUP BY CustomerID
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas
GO

-- ============================================================
-- 3. DimCustomer: sem gaps em ValidFrom/ValidTo
-- ============================================================
PRINT '-- 3. DimCustomer: sem gaps de versao --';
WITH versoes AS (
    SELECT
        CustomerID,
        ValidTo,
        LEAD(ValidFrom) OVER (PARTITION BY CustomerID ORDER BY ValidFrom) AS ProximoValidFrom
    FROM gold.DimCustomer
)
SELECT CustomerID, ValidTo, ProximoValidFrom
FROM versoes
WHERE ValidTo <> '9999-12-31'
  AND ProximoValidFrom IS NOT NULL
  AND DATEDIFF(day, ValidTo, ProximoValidFrom) <> 1;
-- Esperado: 0 linhas (ValidTo + 1 dia = ValidFrom da proxima versao)
GO

-- ============================================================
-- 4. DimProduct: sem duplicata de IsCurrent=1 por ProductID
-- ============================================================
PRINT '-- 4. DimProduct: sem duplicata IsCurrent=1 --';
SELECT ProductID, COUNT(*) AS cnt
FROM gold.DimProduct
WHERE IsCurrent = 1
GROUP BY ProductID
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas
GO

-- ============================================================
-- 5. FactSales: contagem = bronze.OrderDetails
-- ============================================================
PRINT '-- 5. FactSales: contagem vs OrderDetails --';
SELECT
    (SELECT COUNT(*) FROM bronze.OrderDetails) AS OrderDetailsBronze,
    (SELECT COUNT(*) FROM gold.FactSales)      AS FactSalesGold,
    CASE WHEN (SELECT COUNT(*) FROM bronze.OrderDetails)
              = (SELECT COUNT(*) FROM gold.FactSales)
         THEN 'OK' ELSE 'FALHA' END            AS Status;
-- Esperado: 2155 = 2155, Status = OK
GO

-- ============================================================
-- 6. FactSales: orfaos em DimCustomer
-- ============================================================
PRINT '-- 6. FactSales: orfaos CustomerSK --';
SELECT COUNT(*) AS OrfaosCustomer
FROM gold.FactSales f
LEFT JOIN gold.DimCustomer c ON f.CustomerSK = c.CustomerSK
WHERE c.CustomerSK IS NULL;
-- Esperado: 0
GO

-- ============================================================
-- 7. FactSales: orfaos em DimProduct
-- ============================================================
PRINT '-- 7. FactSales: orfaos ProductSK --';
SELECT COUNT(*) AS OrfaosProduto
FROM gold.FactSales f
LEFT JOIN gold.DimProduct p ON f.ProductSK = p.ProductSK
WHERE p.ProductSK IS NULL;
-- Esperado: 0
GO

-- ============================================================
-- 8. FactSales: orfaos em DimDate
-- ============================================================
PRINT '-- 8. FactSales: orfaos OrderDateKey --';
SELECT COUNT(*) AS OrfaosData
FROM gold.FactSales f
LEFT JOIN gold.DimDate d ON f.OrderDateKey = d.DateKey
WHERE d.DateKey IS NULL;
-- Esperado: 0
GO

-- ============================================================
-- 9. FactSales: NetRevenue nunca maior que GrossRevenue
-- ============================================================
PRINT '-- 9. FactSales: NetRevenue <= GrossRevenue --';
SELECT
    MIN(GrossRevenue - NetRevenue) AS MinDiferenca,
    CASE WHEN MIN(GrossRevenue - NetRevenue) >= 0 THEN 'OK' ELSE 'FALHA' END AS Status
FROM gold.FactSales;
-- Esperado: MinDiferenca >= 0
GO

-- ============================================================
-- 10. Reconciliacao de receita: FactSales vs calculo bronze
-- ============================================================
PRINT '-- 10. Reconciliacao NetRevenue --';
SELECT
    CAST(SUM(CAST(UnitPrice * Quantity * (1.0 - Discount) AS DECIMAL(12,2)))
    AS DECIMAL(12,2))           AS NetRevenueBronze,
    (SELECT SUM(NetRevenue) FROM gold.FactSales) AS NetRevenueFato,
    CASE WHEN ABS(
        SUM(CAST(UnitPrice * Quantity * (1.0 - Discount) AS DECIMAL(12,2)))
        - (SELECT SUM(NetRevenue) FROM gold.FactSales)
    ) < 0.01 THEN 'OK' ELSE 'FALHA' END AS Status
FROM bronze.OrderDetails;
-- Esperado: valores iguais, Status = OK
GO

-- ============================================================
-- 11. FactOrderFulfillment: 1 linha por OrderID
-- ============================================================
PRINT '-- 11. FactOrderFulfillment: 1 linha por pedido --';
SELECT OrderID, COUNT(*) AS cnt
FROM gold.FactOrderFulfillment
GROUP BY OrderID
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas
GO

-- ============================================================
-- 12. IsLate consistente com datas
-- ============================================================
PRINT '-- 12. IsLate consistente com ShippedDate vs RequiredDate --';
SELECT COUNT(*) AS Inconsistencias
FROM gold.FactOrderFulfillment f
JOIN bronze.Orders o ON f.OrderID = o.OrderID
WHERE o.ShippedDate IS NOT NULL AND (
    -- IsLate = 1 mas nao atrasou
    (f.IsLate = 1 AND o.ShippedDate <= o.RequiredDate)
    OR
    -- IsLate = 0 mas atrasou
    (f.IsLate = 0 AND o.ShippedDate > o.RequiredDate)
);
-- Esperado: 0
GO

-- ============================================================
-- 13. DimEmployee: sem ManagerName NULL exceto top level
-- ============================================================
PRINT '-- 13. DimEmployee: ManagerName nulo apenas no topo --';
SELECT EmployeeID, FullName, ReportsToID, ManagerName
FROM gold.DimEmployee
WHERE ManagerName IS NULL;
-- Esperado: 1 linha (Andrew Fuller, EmployeeID=2, ReportsToID=NULL)
GO

-- ============================================================
-- 14. FactProductStock: NeedsReorder coerente
-- ============================================================
PRINT '-- 14. FactProductStock: NeedsReorder coerente --';
SELECT COUNT(*) AS Inconsistencias
FROM gold.FactProductStock
WHERE
    (NeedsReorder = 1 AND UnitsInStock > ReorderLevel) OR
    (NeedsReorder = 0 AND UnitsInStock <= ReorderLevel);
-- Esperado: 0
GO

-- ============================================================
-- Validacoes: Novos Padroes (15-20)
-- ============================================================

-- 15. Bridge Table: todas as relacoes EmployeeTerritories estao na bridge
PRINT '-- 15. Bridge completude --';
SELECT
    'Bridge completude' AS check_name,
    COUNT(*) AS missing_in_bridge
FROM bronze.EmployeeTerritories et
JOIN gold.DimEmployee  de ON de.EmployeeID  = et.EmployeeID
JOIN gold.DimTerritory dt ON dt.TerritoryID = et.TerritoryID
WHERE NOT EXISTS (
    SELECT 1 FROM gold.BridgeEmployeeTerritory b
    WHERE b.EmployeeSK = de.EmployeeSK AND b.TerritorySK = dt.TerritorySK
);
-- Esperado: 0 linhas (missing_in_bridge = 0)
GO

-- 16. Junk Dimension: todas as linhas do FactSales tem OrderFlagsSK
PRINT '-- 16. Junk dim sem NULL --';
SELECT
    'Junk dim sem NULL' AS check_name,
    COUNT(*) AS null_flags
FROM gold.FactSales
WHERE OrderFlagsSK IS NULL;
-- Esperado: 0
GO

-- 17. Junk Dimension: todas as 24 combinacoes existem
PRINT '-- 17. Junk dim 24 combos --';
SELECT
    'Junk dim 24 combos' AS check_name,
    COUNT(*) AS total_combos
FROM gold.DimOrderFlags;
-- Esperado: 24
GO

-- 18. SCD3: CurrentCity bate com bronze (estado atual — apos restaurar bronze na simulacao)
PRINT '-- 18. SCD3 cidade atual --';
SELECT
    'SCD3 cidade atual' AS check_name,
    COUNT(*) AS divergencias
FROM gold.DimCustomerSCD3 s3
JOIN bronze.Customers b ON b.CustomerID = s3.CustomerID
WHERE ISNULL(s3.CurrentCity, '') <> ISNULL(b.City, '');
-- Esperado: 0 (apos restaurar bronze na simulacao de 12_scd3.sql)
GO

-- 19. Factless Fact: grain unico (ActivityDateKey, EmployeeSK, TerritorySK)
PRINT '-- 19. Factless grain unico --';
SELECT
    'Factless grain unico' AS check_name,
    COUNT(*) AS duplicatas
FROM (
    SELECT ActivityDateKey, EmployeeSK, TerritorySK, COUNT(*) AS cnt
    FROM gold.FactEmployeeTerritoryActivity
    GROUP BY ActivityDateKey, EmployeeSK, TerritorySK
    HAVING COUNT(*) > 1
) AS dup;
-- Esperado: 0
GO

-- 20. Role-Playing Views: contagem igual a DimDate
PRINT '-- 20. Role-playing views --';
SELECT
    'Role-playing views' AS check_name,
    (SELECT COUNT(*) FROM gold.DimDate)      AS DimDate_rows,
    (SELECT COUNT(*) FROM gold.v_OrderDate)    AS vOrderDate_rows,
    (SELECT COUNT(*) FROM gold.v_RequiredDate) AS vRequiredDate_rows,
    (SELECT COUNT(*) FROM gold.v_ShippedDate)  AS vShippedDate_rows;
-- Esperado: todos os valores iguais
GO

PRINT '';
PRINT '=== FIM DAS VALIDACOES ===';
GO
