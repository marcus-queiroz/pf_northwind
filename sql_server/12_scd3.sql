-- =============================================================
-- 12_scd3.sql
-- Padrao: SCD Tipo 3 (Historico Limitado)
-- Tabela separada: DimCustomerSCD3 (nao altera DimCustomer SCD2)
-- Contexto: guarda apenas a transicao mais recente de
-- City e Country. Simples, mas apenas 1 versao historica.
-- =============================================================

USE NorthwindDW;
GO

-- Passo 1: Carga inicial (todos os clientes do bronze)
CREATE OR ALTER PROCEDURE gold.sp_load_customer_scd3_initial
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM gold.DimCustomerSCD3) RETURN; -- idempotente

    INSERT INTO gold.DimCustomerSCD3
        (CustomerID, CompanyName, ContactName,
         CurrentCity, CurrentCountry, LoadTimestamp)
    SELECT
        CustomerID, CompanyName, ContactName,
        City, Country, GETDATE()
    FROM bronze.Customers;

    PRINT 'DimCustomerSCD3 carga inicial: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' clientes.';
END;
GO

EXEC gold.sp_load_customer_scd3_initial;
GO

-- Passo 2: Procedure de atualizacao SCD3
CREATE OR ALTER PROCEDURE gold.sp_process_customer_scd3
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    -- Detectar mudancas de cidade
    UPDATE scd3
    SET
        PreviousCity     = scd3.CurrentCity,
        CityChangedOn    = @today,
        CurrentCity      = b.City
    FROM gold.DimCustomerSCD3 scd3
    JOIN bronze.Customers b ON b.CustomerID = scd3.CustomerID
    WHERE ISNULL(b.City, '') <> ISNULL(scd3.CurrentCity, '');

    DECLARE @city_changes INT = @@ROWCOUNT;

    -- Detectar mudancas de pais
    UPDATE scd3
    SET
        PreviousCountry  = scd3.CurrentCountry,
        CountryChangedOn = @today,
        CurrentCountry   = b.Country
    FROM gold.DimCustomerSCD3 scd3
    JOIN bronze.Customers b ON b.CustomerID = scd3.CustomerID
    WHERE ISNULL(b.Country, '') <> ISNULL(scd3.CurrentCountry, '');

    DECLARE @country_changes INT = @@ROWCOUNT;

    -- Inserir novos clientes (se houver)
    INSERT INTO gold.DimCustomerSCD3
        (CustomerID, CompanyName, ContactName, CurrentCity, CurrentCountry, LoadTimestamp)
    SELECT b.CustomerID, b.CompanyName, b.ContactName, b.City, b.Country, GETDATE()
    FROM bronze.Customers b
    WHERE NOT EXISTS (
        SELECT 1 FROM gold.DimCustomerSCD3 s WHERE s.CustomerID = b.CustomerID
    );

    PRINT 'SCD3: ' + CAST(@city_changes AS VARCHAR) + ' mudancas de cidade, '
        + CAST(@country_changes AS VARCHAR) + ' de pais.';
END;
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
UPDATE bronze.Customers SET City = 'Berlin'       WHERE CustomerID = 'ALFKI';
UPDATE bronze.Customers SET City = 'M?xico D.F.'  WHERE CustomerID = 'ANATR';
UPDATE bronze.Customers SET City = 'Madrid'        WHERE CustomerID = 'BOLID';
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
