-- ============================================================
-- 04_silver_scd2.sql
-- Procedures: gold.sp_process_customers_scd2
--             gold.sp_process_products_scd2
-- Tecnica: SCD Tipo 2 — detectar mudanca, expirar versao atual, inserir nova versao
-- Atributos rastreados:
--   DimCustomer: ContactName, ContactTitle, City, Country
--   DimProduct:  UnitPrice, Discontinued
-- ============================================================

USE NorthwindDW;
GO

-- ============================================================
-- DimCustomer — SCD Tipo 2
-- ============================================================
CREATE OR ALTER PROCEDURE gold.sp_process_customers_scd2
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    BEGIN TRY

    -- =========================================================
    -- PASSO 1: Carga inicial (tabela vazia)
    -- ValidFrom = '1900-01-01' para fatos historicos (1996-1998)
    -- =========================================================
    IF NOT EXISTS (SELECT 1 FROM gold.DimCustomer)
    BEGIN
        INSERT INTO gold.DimCustomer
            (CustomerID, CompanyName, ContactName, ContactTitle,
             City, Country, ValidFrom, ValidTo, IsCurrent)
        SELECT
            CustomerID, CompanyName, ContactName, ContactTitle,
            City, Country,
            '1900-01-01', '9999-12-31', 1
        FROM bronze.Customers;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.DimCustomer', GETDATE(), @@ROWCOUNT, 'OK', 'carga inicial');
        RETURN;
    END;

    -- =========================================================
    -- PASSO 2: Detectar mudancas — guardar em tabela temporaria
    -- =========================================================
    CREATE TABLE #changed_customers (CustomerID NCHAR(5));

    INSERT INTO #changed_customers (CustomerID)
    SELECT b.CustomerID
    FROM bronze.Customers b
    JOIN gold.DimCustomer d
        ON d.CustomerID = b.CustomerID AND d.IsCurrent = 1
    WHERE
        ISNULL(b.ContactName,  '') <> ISNULL(d.ContactName,  '') OR
        ISNULL(b.ContactTitle, '') <> ISNULL(d.ContactTitle, '') OR
        ISNULL(b.City,         '') <> ISNULL(d.City,         '') OR
        ISNULL(b.Country,      '') <> ISNULL(d.Country,      '');

    -- PASSO 2a: Expirar versao atual dos que mudaram
    UPDATE d
    SET
        d.ValidTo   = DATEADD(day, -1, @today),
        d.IsCurrent = 0
    FROM gold.DimCustomer d
    JOIN #changed_customers c ON d.CustomerID = c.CustomerID AND d.IsCurrent = 1;

    -- PASSO 2b: Inserir nova versao para os que mudaram
    INSERT INTO gold.DimCustomer
        (CustomerID, CompanyName, ContactName, ContactTitle,
         City, Country, ValidFrom, ValidTo, IsCurrent)
    SELECT
        b.CustomerID, b.CompanyName, b.ContactName, b.ContactTitle,
        b.City, b.Country,
        @today, '9999-12-31', 1
    FROM bronze.Customers b
    JOIN #changed_customers c ON b.CustomerID = c.CustomerID;

    DROP TABLE #changed_customers;

    -- =========================================================
    -- PASSO 3: Inserir clientes novos (nao existem em silver)
    -- =========================================================
    INSERT INTO gold.DimCustomer
        (CustomerID, CompanyName, ContactName, ContactTitle,
         City, Country, ValidFrom, ValidTo, IsCurrent)
    SELECT
        b.CustomerID, b.CompanyName, b.ContactName, b.ContactTitle,
        b.City, b.Country,
        @today, '9999-12-31', 1
    FROM bronze.Customers b
    WHERE NOT EXISTS (
        SELECT 1 FROM gold.DimCustomer d WHERE d.CustomerID = b.CustomerID
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.DimCustomer', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.DimCustomer', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- ============================================================
-- DimProduct — SCD Tipo 2 com denormalizacao
-- ============================================================
CREATE OR ALTER PROCEDURE gold.sp_process_products_scd2
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today DATE = CAST(GETDATE() AS DATE);

    BEGIN TRY

    -- =========================================================
    -- PASSO 1: Carga inicial (tabela vazia)
    -- =========================================================
    IF NOT EXISTS (SELECT 1 FROM gold.DimProduct)
    BEGIN
        INSERT INTO gold.DimProduct
            (ProductID, ProductName, CategoryName, SupplierCompany,
             UnitPrice, QuantityPerUnit, Discontinued,
             ValidFrom, ValidTo, IsCurrent)
        SELECT
            p.ProductID,
            p.ProductName,
            c.CategoryName,
            s.CompanyName      AS SupplierCompany,
            p.UnitPrice,
            p.QuantityPerUnit,
            p.Discontinued,
            '1900-01-01', '9999-12-31', 1
        FROM bronze.Products p
        LEFT JOIN bronze.Categories c ON p.CategoryID = c.CategoryID
        LEFT JOIN bronze.Suppliers  s ON p.SupplierID = s.SupplierID;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.DimProduct', GETDATE(), @@ROWCOUNT, 'OK', 'carga inicial');
        RETURN;
    END;

    -- =========================================================
    -- PASSO 2: Detectar mudancas em UnitPrice ou Discontinued
    -- =========================================================
    CREATE TABLE #changed_products (ProductID INT);

    INSERT INTO #changed_products (ProductID)
    SELECT p.ProductID
    FROM bronze.Products p
    JOIN gold.DimProduct d ON d.ProductID = p.ProductID AND d.IsCurrent = 1
    WHERE
        ISNULL(p.UnitPrice, 0)    <> ISNULL(d.UnitPrice, 0) OR
        p.Discontinued             <> d.Discontinued;

    -- PASSO 2a: Expirar versao atual
    UPDATE d
    SET
        d.ValidTo   = DATEADD(day, -1, @today),
        d.IsCurrent = 0
    FROM gold.DimProduct d
    JOIN #changed_products c ON d.ProductID = c.ProductID AND d.IsCurrent = 1;

    -- PASSO 2b: Inserir nova versao (com denormalizacao atualizada)
    INSERT INTO gold.DimProduct
        (ProductID, ProductName, CategoryName, SupplierCompany,
         UnitPrice, QuantityPerUnit, Discontinued,
         ValidFrom, ValidTo, IsCurrent)
    SELECT
        p.ProductID,
        p.ProductName,
        cat.CategoryName,
        sup.CompanyName  AS SupplierCompany,
        p.UnitPrice,
        p.QuantityPerUnit,
        p.Discontinued,
        @today, '9999-12-31', 1
    FROM bronze.Products p
    LEFT JOIN bronze.Categories cat ON p.CategoryID = cat.CategoryID
    LEFT JOIN bronze.Suppliers  sup ON p.SupplierID = sup.SupplierID
    JOIN #changed_products c ON p.ProductID = c.ProductID;

    DROP TABLE #changed_products;

    -- =========================================================
    -- PASSO 3: Inserir produtos novos
    -- =========================================================
    INSERT INTO gold.DimProduct
        (ProductID, ProductName, CategoryName, SupplierCompany,
         UnitPrice, QuantityPerUnit, Discontinued,
         ValidFrom, ValidTo, IsCurrent)
    SELECT
        p.ProductID,
        p.ProductName,
        c.CategoryName,
        s.CompanyName,
        p.UnitPrice,
        p.QuantityPerUnit,
        p.Discontinued,
        @today, '9999-12-31', 1
    FROM bronze.Products p
    LEFT JOIN bronze.Categories c ON p.CategoryID = c.CategoryID
    LEFT JOIN bronze.Suppliers  s ON p.SupplierID = s.SupplierID
    WHERE NOT EXISTS (
        SELECT 1 FROM gold.DimProduct d WHERE d.ProductID = p.ProductID
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.DimProduct', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.DimProduct', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO
