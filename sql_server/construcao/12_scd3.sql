-- =============================================================
-- 12_scd3.sql
-- Padrao: SCD Tipo 3 (Historico Limitado)
-- Tabela separada: DimCustomerSCD3 (nao altera DimCustomer SCD2)
-- Contexto: guarda apenas a transicao mais recente de
-- City e Country. Simples, mas apenas 1 versao historica.
--
-- So definem as procedures. Execucao e exploracao (com
-- simulacao de mudanca de cidade/pais):
-- sql_server/labs/12_scd3_lab.sql
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
