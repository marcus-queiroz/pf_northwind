-- ============================================================
-- 12_scd3_lab.sql
-- Lab: carrega o SCD Tipo 3 e simula uma mudanca de cidade/pais
-- para demonstrar o historico limitado (1 versao anterior).
-- Northwind e estatico — a simulacao altera bronze.Customers e
-- restaura o valor original ao final.
-- ============================================================

USE NorthwindDW;
GO

-- PASSO 1: Carga inicial (idempotente — nao refaz se ja existir)
EXEC gold.sp_load_customer_scd3_initial;
GO

-- ---------------------------------------------------------------
-- SIMULACAO: Atualizar 3 clientes no bronze para demonstrar SCD3
-- (dados sinteticos — Northwind e estatico)
-- ---------------------------------------------------------------
PRINT '--- Estado ANTES ---';
SELECT CustomerID, CurrentCity, PreviousCity, CityChangedOn
FROM gold.DimCustomerSCD3
WHERE CustomerID IN ('ALFKI', 'ANATR', 'BOLID');
GO

UPDATE bronze.Customers SET City = 'Lyon'     WHERE CustomerID = 'ALFKI';  -- era Berlin
UPDATE bronze.Customers SET City = 'Madrid'   WHERE CustomerID = 'ANATR';  -- era Mexico D.F.
UPDATE bronze.Customers SET City = 'Valencia' WHERE CustomerID = 'BOLID';  -- era Madrid
GO

-- PASSO 2: Rodar a procedure de atualizacao
EXEC gold.sp_process_customer_scd3;
GO

PRINT '--- Estado DEPOIS (historico limitado aplicado) ---';
SELECT
    CustomerID,
    CurrentCity      AS CidadeAtual,
    PreviousCity     AS CidadeAnterior,
    CityChangedOn    AS DataMudanca
FROM gold.DimCustomerSCD3
WHERE CustomerID IN ('ALFKI', 'ANATR', 'BOLID');
GO

-- Restaurar bronze para estado original
UPDATE bronze.Customers SET City = 'Berlin'      WHERE CustomerID = 'ALFKI';
UPDATE bronze.Customers SET City = 'México D.F.' WHERE CustomerID = 'ANATR';
UPDATE bronze.Customers SET City = 'Madrid'      WHERE CustomerID = 'BOLID';
GO

-- ---------------------------------------------------------------
-- DEMO: Clientes que mudaram de cidade/pais (apos simulacao)
-- ---------------------------------------------------------------
PRINT '-- DEMO: Historico SCD3 --';
SELECT
    CustomerID,
    CompanyName,
    CurrentCity      AS CidadeAtual,
    PreviousCity     AS CidadeAnterior,
    CityChangedOn    AS MudouEm,
    CurrentCountry,
    PreviousCountry,
    CountryChangedOn
FROM gold.DimCustomerSCD3
WHERE PreviousCity IS NOT NULL OR PreviousCountry IS NOT NULL
ORDER BY CityChangedOn DESC;
GO

-- Comparacao direta com SCD2:
-- SCD3: apenas 1 versao anterior, atualiza no mesmo registro
-- SCD2: historico completo, nova linha por mudanca
-- SCD1: sem historico, sobrescreve
PRINT '-- DEMO: Comparacao SCD2 vs SCD3 --';
SELECT TOP 5
    s2.CustomerID,
    s2.ContactName,
    s2.City      AS CidadeSCD2_VersionAtual,
    s2.ValidFrom,
    s2.ValidTo,
    s3.CurrentCity   AS CidadeSCD3_Atual,
    s3.PreviousCity  AS CidadeSCD3_Anterior
FROM gold.DimCustomer  s2
JOIN gold.DimCustomerSCD3 s3 ON s3.CustomerID = s2.CustomerID
WHERE s2.IsCurrent = 1;
GO
