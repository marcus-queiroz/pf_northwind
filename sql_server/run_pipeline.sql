-- ============================================================
-- run_pipeline.sql — Visão geral do pipeline Northwind DW
-- ============================================================
-- Este script executa as procedures do pipeline em sequência.
--
-- PRÉ-REQUISITO: as estruturas e procedures precisam existir.
-- Antes de rodar este script, abra e execute cada arquivo
-- abaixo na ordem indicada:
--
--   00_create_northwind_source.sql  ← banco Northwind (fonte OLTP)
--   01_setup.sql                    ← banco NorthwindDW, schemas e tabelas
--   02_bronze_ingest.sql            ← cria bronze.sp_ingest_bronze
--   03_gold_dims.sql                ← cria gold.sp_process_dims
--   04_gold_scd2.sql                ← cria gold.sp_process_customers_scd2
--                                      e gold.sp_process_products_scd2
--   05_gold_fact_sales.sql          ← cria gold.sp_process_fact_sales
--   06_gold_fact_fulfillment.sql    ← cria gold.sp_process_fact_fulfillment
--   07_gold_fact_stock.sql          ← cria gold.sp_process_fact_stock
--   10_bridge_table.sql             ← cria gold.sp_process_bridge_employee_territory
--   12_scd3.sql                     ← cria gold.sp_load_customer_scd3_initial
--                                      e gold.sp_process_customer_scd3
--   13_factless_fact.sql            ← cria gold.sp_process_factless_activity
--
-- Nota: os scripts abaixo não usam procedures — execute-os
-- diretamente no SSMS (abra e rode cada um separadamente):
--
--   08_analytics.sql      ← 10 queries analíticas com framing de negócio
--   09_validation.sql     ← 20 verificações de integridade do modelo
--   11_junk_dimension.sql ← popula DimOrderFlags e atualiza FactSales
--   14_role_playing.sql   ← demonstração de role-playing + degenerate dimension
-- ============================================================

USE NorthwindDW;
GO

-- -------------------------------------------------------
-- Bronze
-- Procedure criada em: 02_bronze_ingest.sql
-- -------------------------------------------------------
EXEC bronze.sp_ingest_bronze;
GO

-- -------------------------------------------------------
-- Gold — Dimensões SCD1 + DimDate
-- Procedure criada em: 03_gold_dims.sql
-- -------------------------------------------------------
EXEC gold.sp_process_dims;
GO

-- Gold — DimCustomer (SCD2)
-- Procedure criada em: 04_gold_scd2.sql
EXEC gold.sp_process_customers_scd2;
GO

-- Gold — DimProduct (SCD2)
-- Procedure criada em: 04_gold_scd2.sql
EXEC gold.sp_process_products_scd2;
GO

-- -------------------------------------------------------
-- Gold — Fatos
-- -------------------------------------------------------

-- FactSales (transacional)
-- Procedure criada em: 05_gold_fact_sales.sql
EXEC gold.sp_process_fact_sales;
GO

-- FactOrderFulfillment (accumulating snapshot)
-- Procedure criada em: 06_gold_fact_fulfillment.sql
EXEC gold.sp_process_fact_fulfillment;
GO

-- FactProductStock (periodic snapshot)
-- Procedure criada em: 07_gold_fact_stock.sql
EXEC gold.sp_process_fact_stock;
GO

-- -------------------------------------------------------
-- Análise e validação
-- -------------------------------------------------------

-- 08_analytics.sql e 09_validation.sql não usam procedures.
-- Abra e execute cada arquivo diretamente no SSMS.

-- -------------------------------------------------------
-- Padrões avançados
-- -------------------------------------------------------

-- BridgeEmployeeTerritory (M:N Employee ↔ Territory)
-- Procedure criada em: 10_bridge_table.sql
EXEC gold.sp_process_bridge_employee_territory;
GO

-- DimOrderFlags (Junk Dimension)
-- 11_junk_dimension.sql não usa procedure.
-- Abra e execute o arquivo diretamente no SSMS.

-- DimCustomerSCD3 — carga inicial
-- Procedure criada em: 12_scd3.sql
EXEC gold.sp_load_customer_scd3_initial;
GO

-- DimCustomerSCD3 — atualização incremental
-- Procedure criada em: 12_scd3.sql
EXEC gold.sp_process_customer_scd3;
GO

-- FactEmployeeTerritoryActivity (Factless Fact)
-- Procedure criada em: 13_factless_fact.sql
EXEC gold.sp_process_factless_activity;
GO

-- Role-Playing Dimension + Degenerate Dimension
-- 14_role_playing.sql não usa procedure — as views já foram criadas em 01_setup.sql.
-- Abra e execute o arquivo diretamente no SSMS para ver as queries de demonstração.

-- ============================================================
-- Resultado: o que foi construído
-- ============================================================

-- -------------------------------------------------------
-- Contagem de linhas por tabela
-- -------------------------------------------------------
SELECT 'DimCustomer'                  AS Tabela, COUNT(*) AS Linhas FROM gold.DimCustomer
UNION ALL
SELECT 'DimProduct',                             COUNT(*) FROM gold.DimProduct
UNION ALL
SELECT 'DimEmployee',                            COUNT(*) FROM gold.DimEmployee
UNION ALL
SELECT 'DimCategory',                            COUNT(*) FROM gold.DimCategory
UNION ALL
SELECT 'DimSupplier',                            COUNT(*) FROM gold.DimSupplier
UNION ALL
SELECT 'DimShipper',                             COUNT(*) FROM gold.DimShipper
UNION ALL
SELECT 'DimTerritory',                           COUNT(*) FROM gold.DimTerritory
UNION ALL
SELECT 'DimDate',                                COUNT(*) FROM gold.DimDate
UNION ALL
SELECT 'FactSales',                              COUNT(*) FROM gold.FactSales
UNION ALL
SELECT 'FactOrderFulfillment',                   COUNT(*) FROM gold.FactOrderFulfillment
UNION ALL
SELECT 'FactProductStock',                       COUNT(*) FROM gold.FactProductStock
UNION ALL
SELECT 'BridgeEmployeeTerritory',                COUNT(*) FROM gold.BridgeEmployeeTerritory
UNION ALL
SELECT 'DimOrderFlags',                          COUNT(*) FROM gold.DimOrderFlags
UNION ALL
SELECT 'DimCustomerSCD3',                        COUNT(*) FROM gold.DimCustomerSCD3
UNION ALL
SELECT 'FactEmployeeTerritoryActivity',          COUNT(*) FROM gold.FactEmployeeTerritoryActivity
ORDER BY Tabela;

-- -------------------------------------------------------
-- Receita líquida por categoria e ano
-- Join entre FactSales, DimProduct, DimCategory e DimDate
-- -------------------------------------------------------
SELECT
    c.CategoryName,
    d.Year                              AS Ano,
    COUNT(DISTINCT f.OrderID)           AS TotalPedidos,
    CAST(SUM(f.NetRevenue) AS DECIMAL(12,2)) AS ReceitaLiquida
FROM gold.FactSales           f
JOIN gold.DimProduct          p ON f.ProductKey      = p.ProductKey
JOIN gold.DimCategory         c ON p.CategoryKey     = c.CategoryKey
JOIN gold.DimDate             d ON f.OrderDateKey     = d.DateKey
WHERE p.IsCurrent = 1
GROUP BY c.CategoryName, d.Year
ORDER BY d.Year, ReceitaLiquida DESC;

-- -------------------------------------------------------
-- SLA de entrega por transportadora
-- Usa FactOrderFulfillment (accumulating snapshot)
-- -------------------------------------------------------
SELECT
    s.CompanyName                                   AS Transportadora,
    COUNT(*)                                        AS TotalPedidos,
    AVG(CAST(f.DaysToShip AS FLOAT))                AS MediaDiasEnvio,
    SUM(CASE WHEN f.IsLate = 1 THEN 1 ELSE 0 END)  AS PedidosAtrasados,
    CAST(
        100.0 * SUM(CASE WHEN f.IsLate = 1 THEN 1 ELSE 0 END) / COUNT(*)
    AS DECIMAL(5,1))                                AS PctAtraso
FROM gold.FactOrderFulfillment f
JOIN gold.DimShipper           s ON f.ShipperKey = s.ShipperKey
WHERE f.ShippedDateKey IS NOT NULL
GROUP BY s.CompanyName
ORDER BY MediaDiasEnvio;
