-- ============================================================
-- 08_analytics.sql
-- 10 queries analiticas sobre NorthwindDW
-- ============================================================

USE NorthwindDW;
GO

-- ============================================================
-- 1. Receita bruta vs liquida por categoria de produto
-- ============================================================
SELECT
    p.CategoryName,
    COUNT(DISTINCT f.OrderID)               AS Pedidos,
    SUM(f.GrossRevenue)                     AS GrossRevenue,
    SUM(f.NetRevenue)                       AS NetRevenue,
    SUM(f.GrossRevenue - f.NetRevenue)      AS DescontoTotal,
    CAST(AVG(f.Discount) * 100 AS DECIMAL(5,2)) AS DescontoMedioPct
FROM gold.FactSales f
JOIN gold.DimProduct p ON f.ProductSK = p.ProductSK
GROUP BY p.CategoryName
ORDER BY NetRevenue DESC;
GO

-- ============================================================
-- 2. Top 10 clientes por NetRevenue
-- ============================================================
SELECT TOP 10
    c.CompanyName,
    c.Country,
    COUNT(DISTINCT f.OrderID)               AS Pedidos,
    SUM(f.NetRevenue)                       AS NetRevenue,
    AVG(f.NetRevenue)                       AS TicketMedio
FROM gold.FactSales f
JOIN gold.DimCustomer c ON f.CustomerSK = c.CustomerSK
GROUP BY c.CompanyName, c.Country
ORDER BY NetRevenue DESC;
GO

-- ============================================================
-- 3. Performance de entrega por Shipper (Accumulating Snapshot)
-- ============================================================
SELECT
    s.CompanyName                                                   AS Shipper,
    COUNT(*)                                                        AS TotalEntregues,
    SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)                  AS OnTime,
    SUM(CASE WHEN f.IsLate = 1 THEN 1 ELSE 0 END)                  AS Atrasados,
    CAST(100.0 * SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,1))                    AS OnTimePct,
    CAST(AVG(CAST(f.DaysToShip AS FLOAT)) AS DECIMAL(5,1))         AS MediaDiasEnvio
FROM gold.FactOrderFulfillment f
JOIN gold.DimShipper s ON f.ShipperSK = s.ShipperSK
WHERE f.ShippedDateKey IS NOT NULL
GROUP BY s.CompanyName
ORDER BY OnTimePct DESC;
GO

-- ============================================================
-- 4. Analise SCD2: receita por pais do cliente NO MOMENTO DA VENDA
--    (demonstra o valor do SCD2 — nao o pais atual)
-- ============================================================
SELECT
    c.Country                               AS PaisNaMomentoVenda,
    d.Year                                  AS Ano,
    COUNT(DISTINCT f.OrderID)               AS Pedidos,
    SUM(f.NetRevenue)                       AS NetRevenue,
    RANK() OVER (
        PARTITION BY d.Year
        ORDER BY SUM(f.NetRevenue) DESC
    )                                       AS Rank
FROM gold.FactSales f
JOIN gold.DimCustomer c ON f.CustomerSK = c.CustomerSK
JOIN gold.DimDate     d ON f.OrderDateKey = d.DateKey
GROUP BY c.Country, d.Year
ORDER BY d.Year, Rank;
GO

-- ============================================================
-- 5. Historico de preco por produto (versoes SCD2)
--    + receita total por versao de preco
-- ============================================================
SELECT
    p.ProductName,
    p.CategoryName,
    p.UnitPrice       AS PrecoNaVersao,
    p.ValidFrom,
    p.ValidTo,
    COUNT(f.SalesSK)  AS Vendas,
    ISNULL(SUM(f.NetRevenue), 0) AS ReceitaNaVersao
FROM gold.DimProduct p
LEFT JOIN gold.FactSales f ON f.ProductSK = p.ProductSK
GROUP BY p.ProductName, p.CategoryName, p.UnitPrice, p.ValidFrom, p.ValidTo
ORDER BY p.ProductName, p.ValidFrom;
GO

-- ============================================================
-- 6. Hierarquia de funcionarios: receita por gestor e subordinado
-- ============================================================
SELECT
    ISNULL(e.ManagerName, '(Presidente)')  AS Gestor,
    e.FullName                             AS Funcionario,
    e.Title,
    COUNT(f.SalesSK)                       AS Transacoes,
    SUM(f.NetRevenue)                      AS NetRevenue,
    AVG(f.NetRevenue)                      AS TicketMedio
FROM gold.FactSales f
JOIN gold.DimEmployee e ON f.EmployeeSK = e.EmployeeSK
GROUP BY e.ManagerName, e.FullName, e.Title
ORDER BY e.ManagerName, NetRevenue DESC;
GO

-- ============================================================
-- 7. Sazonalidade: NetRevenue por mes e trimestre
-- ============================================================
SELECT
    d.Year,
    d.Quarter,
    d.Month,
    d.MonthName,
    COUNT(DISTINCT f.OrderID)  AS Pedidos,
    SUM(f.NetRevenue)          AS NetRevenue,
    SUM(SUM(f.NetRevenue)) OVER (
        PARTITION BY d.Year, d.Quarter
        ORDER BY d.Month
    )                          AS AcumuladoTrimestre
FROM gold.FactSales f
JOIN gold.DimDate d ON f.OrderDateKey = d.DateKey
GROUP BY d.Year, d.Quarter, d.Month, d.MonthName
ORDER BY d.Year, d.Month;
GO

-- ============================================================
-- 8. Produtos com reposicao necessaria (ultimo snapshot)
-- ============================================================
SELECT
    p.ProductName,
    p.CategoryName,
    fs.UnitsInStock,
    fs.ReorderLevel,
    fs.UnitsOnOrder,
    fs.UnitsInStock - fs.ReorderLevel   AS EstoqueAcimaReorder,
    fs.SnapshotDateKey
FROM gold.FactProductStock fs
JOIN gold.DimProduct p ON fs.ProductSK = p.ProductSK
WHERE fs.NeedsReorder = 1
  AND fs.SnapshotDateKey = (
      SELECT MAX(SnapshotDateKey) FROM gold.FactProductStock
  )
ORDER BY EstoqueAcimaReorder;
GO

-- ============================================================
-- 9. Desconto medio por categoria e impacto na receita
-- ============================================================
SELECT
    p.CategoryName,
    CAST(AVG(f.Discount) * 100 AS DECIMAL(5,2))             AS DescontoMedioPct,
    SUM(f.GrossRevenue)                                     AS GrossRevenue,
    SUM(f.NetRevenue)                                       AS NetRevenue,
    SUM(f.GrossRevenue - f.NetRevenue)                      AS ReceitaPerdida,
    CAST(100.0 * SUM(f.GrossRevenue - f.NetRevenue)
         / NULLIF(SUM(f.GrossRevenue), 0) AS DECIMAL(5,2))  AS PctPerdidaPorDesconto
FROM gold.FactSales f
JOIN gold.DimProduct p ON f.ProductSK = p.ProductSK
GROUP BY p.CategoryName
ORDER BY PctPerdidaPorDesconto DESC;
GO

-- ============================================================
-- 10. Pedidos por pais de destino com lead time medio
-- ============================================================
SELECT
    f.ShipCountry,
    COUNT(DISTINCT f.OrderID)                               AS TotalPedidos,
    SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)          AS Pontuais,
    SUM(CASE WHEN f.IsLate = 1 THEN 1 ELSE 0 END)          AS Atrasados,
    CAST(AVG(CAST(f.DaysToShip AS FLOAT)) AS DECIMAL(5,1)) AS LeadTimeMedio,
    CAST(100.0 * SUM(CASE WHEN f.IsLate = 0 THEN 1 ELSE 0 END)
         / NULLIF(COUNT(CASE WHEN f.ShippedDateKey IS NOT NULL THEN 1 END), 0)
    AS DECIMAL(5,1))                                       AS OnTimePct
FROM gold.FactOrderFulfillment f
GROUP BY f.ShipCountry
ORDER BY TotalPedidos DESC;
GO
