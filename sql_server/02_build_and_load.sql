-- ============================================================
-- 02_build_and_load.sql — GERADO. Não editar à mão.
--
-- Concatenação das procedures de sql_server/construcao/ mais a
-- sequência de EXEC que constrói o modelo gold de ponta a ponta.
-- Fonte: sql_server/construcao/ — edite lá e rode
--   .tools/gen_build_and_load.sh para regenerar este arquivo.
-- ============================================================

-- ---- fonte: construcao/02_bronze_ingest.sql ----
-- ============================================================
-- 02_bronze_ingest.sql
-- Procedure: bronze.sp_ingest_bronze
-- Tecnica: Full Load — TRUNCATE + INSERT SELECT de cada tabela dbo.* -> bronze.*
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE bronze.sp_ingest_bronze
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rows INT;

    -- Customers
    BEGIN TRY
        TRUNCATE TABLE bronze.Customers;
        INSERT INTO bronze.Customers
            (CustomerID, CompanyName, ContactName, ContactTitle,
             Address, City, Region, PostalCode, Country, Phone, Fax)
        SELECT
            CustomerID, CompanyName, ContactName, ContactTitle,
            Address, City, Region, PostalCode, Country, Phone, Fax
        FROM Northwind.dbo.Customers;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Customers', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Customers', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Employees (excluir Photo — BLOB)
    BEGIN TRY
        TRUNCATE TABLE bronze.Employees;
        INSERT INTO bronze.Employees
            (EmployeeID, LastName, FirstName, Title, TitleOfCourtesy,
             BirthDate, HireDate, Address, City, Region, PostalCode,
             Country, HomePhone, Extension, ReportsTo, PhotoPath)
        SELECT
            EmployeeID, LastName, FirstName, Title, TitleOfCourtesy,
            BirthDate, HireDate, Address, City, Region, PostalCode,
            Country, HomePhone, Extension, ReportsTo, PhotoPath
        FROM Northwind.dbo.Employees;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Employees', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Employees', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Products
    BEGIN TRY
        TRUNCATE TABLE bronze.Products;
        INSERT INTO bronze.Products
            (ProductID, ProductName, SupplierID, CategoryID, QuantityPerUnit,
             UnitPrice, UnitsInStock, UnitsOnOrder, ReorderLevel, Discontinued)
        SELECT
            ProductID, ProductName, SupplierID, CategoryID, QuantityPerUnit,
            UnitPrice, UnitsInStock, UnitsOnOrder, ReorderLevel, Discontinued
        FROM Northwind.dbo.Products;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Products', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Products', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Categories (excluir Picture — BLOB)
    BEGIN TRY
        TRUNCATE TABLE bronze.Categories;
        INSERT INTO bronze.Categories
            (CategoryID, CategoryName, Description)
        SELECT
            CategoryID, CategoryName,
            CAST(Description AS VARCHAR(200))
        FROM Northwind.dbo.Categories;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Categories', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Categories', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Suppliers
    BEGIN TRY
        TRUNCATE TABLE bronze.Suppliers;
        INSERT INTO bronze.Suppliers
            (SupplierID, CompanyName, ContactName, ContactTitle,
             Address, City, Region, PostalCode, Country, Phone, Fax)
        SELECT
            SupplierID, CompanyName, ContactName, ContactTitle,
            Address, City, Region, PostalCode, Country, Phone, Fax
        FROM Northwind.dbo.Suppliers;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Suppliers', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Suppliers', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Shippers
    BEGIN TRY
        TRUNCATE TABLE bronze.Shippers;
        INSERT INTO bronze.Shippers (ShipperID, CompanyName, Phone)
        SELECT ShipperID, CompanyName, Phone
        FROM Northwind.dbo.Shippers;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Shippers', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Shippers', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Orders
    BEGIN TRY
        TRUNCATE TABLE bronze.Orders;
        INSERT INTO bronze.Orders
            (OrderID, CustomerID, EmployeeID, OrderDate, RequiredDate,
             ShippedDate, ShipVia, Freight, ShipName, ShipAddress,
             ShipCity, ShipRegion, ShipPostalCode, ShipCountry)
        SELECT
            OrderID, CustomerID, EmployeeID, OrderDate, RequiredDate,
            ShippedDate, ShipVia, Freight, ShipName, ShipAddress,
            ShipCity, ShipRegion, ShipPostalCode, ShipCountry
        FROM Northwind.dbo.Orders;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Orders', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Orders', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- OrderDetails (origem: [Order Details] com espaco)
    BEGIN TRY
        TRUNCATE TABLE bronze.OrderDetails;
        INSERT INTO bronze.OrderDetails
            (OrderID, ProductID, UnitPrice, Quantity, Discount)
        SELECT
            OrderID, ProductID, UnitPrice, Quantity, Discount
        FROM Northwind.dbo.[Order Details];
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.OrderDetails', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.OrderDetails', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Territories
    BEGIN TRY
        TRUNCATE TABLE bronze.Territories;
        INSERT INTO bronze.Territories
            (TerritoryID, TerritoryDescription, RegionID)
        SELECT
            TerritoryID, RTRIM(TerritoryDescription), RegionID
        FROM Northwind.dbo.Territories;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Territories', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Territories', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- Region
    BEGIN TRY
        TRUNCATE TABLE bronze.Region;
        INSERT INTO bronze.Region (RegionID, RegionDescription)
        SELECT RegionID, RTRIM(RegionDescription)
        FROM Northwind.dbo.Region;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.Region', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.Region', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

    -- EmployeeTerritories
    BEGIN TRY
        TRUNCATE TABLE bronze.EmployeeTerritories;
        INSERT INTO bronze.EmployeeTerritories (EmployeeID, TerritoryID)
        SELECT EmployeeID, TerritoryID
        FROM Northwind.dbo.EmployeeTerritories;
        SET @rows = @@ROWCOUNT;
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
        VALUES ('bronze.EmployeeTerritories', GETDATE(), @rows, 'OK');
    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('bronze.EmployeeTerritories', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;

END;
GO

-- ---- fonte: construcao/03_gold_dims.sql ----
-- ============================================================
-- 03_silver_dims.sql
-- Procedure: gold.sp_process_dims
-- Tecnica: MERGE (upsert SCD1) para 5 dimensoes + DimDate (serie)
-- Dimensoes: DimEmployee, DimCategory, DimSupplier, DimShipper, DimTerritory, DimDate
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_dims
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @total  INT = 0;
    DECLARE @errMsg VARCHAR(500);

    BEGIN TRY

    -- =========================================================
    -- DimEmployee — SCD1 com hierarquia achatada + territorios
    -- =========================================================
    MERGE gold.DimEmployee AS tgt
    USING (
        SELECT
            e.EmployeeID,
            e.FirstName + ' ' + e.LastName                    AS FullName,
            e.Title,
            CAST(e.HireDate AS DATE)                          AS HireDate,
            e.City,
            e.Country,
            e.ReportsTo                                       AS ReportsToID,
            m.FirstName + ' ' + m.LastName                   AS ManagerName,
            STRING_AGG(RTRIM(t.TerritoryDescription), ', ')
                WITHIN GROUP (ORDER BY t.TerritoryDescription) AS TerritoryList,
            r.RegionDescription                               AS RegionName
        FROM bronze.Employees e
        LEFT JOIN bronze.Employees m
            ON e.ReportsTo = m.EmployeeID
        LEFT JOIN bronze.EmployeeTerritories et
            ON e.EmployeeID = et.EmployeeID
        LEFT JOIN bronze.Territories t
            ON et.TerritoryID = t.TerritoryID
        LEFT JOIN bronze.Region r
            ON t.RegionID = r.RegionID
        GROUP BY
            e.EmployeeID, e.FirstName, e.LastName, e.Title, e.HireDate,
            e.City, e.Country, e.ReportsTo,
            m.FirstName, m.LastName, r.RegionDescription
    ) AS src ON tgt.EmployeeID = src.EmployeeID
    WHEN MATCHED THEN UPDATE SET
        tgt.FullName      = src.FullName,
        tgt.Title         = src.Title,
        tgt.HireDate      = src.HireDate,
        tgt.City          = src.City,
        tgt.Country       = src.Country,
        tgt.ReportsToID   = src.ReportsToID,
        tgt.ManagerName   = src.ManagerName,
        tgt.TerritoryList = src.TerritoryList,
        tgt.RegionName    = src.RegionName,
        tgt.LoadTimestamp = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (EmployeeID, FullName, Title, HireDate, City, Country,
         ReportsToID, ManagerName, TerritoryList, RegionName)
    VALUES
        (src.EmployeeID, src.FullName, src.Title, src.HireDate, src.City, src.Country,
         src.ReportsToID, src.ManagerName, src.TerritoryList, src.RegionName);
    SET @total += @@ROWCOUNT;

    -- =========================================================
    -- DimCategory — MERGE simples (8 linhas)
    -- =========================================================
    MERGE gold.DimCategory AS tgt
    USING (
        SELECT CategoryID, CategoryName, Description
        FROM bronze.Categories
    ) AS src ON tgt.CategoryID = src.CategoryID
    WHEN MATCHED THEN UPDATE SET
        tgt.CategoryName  = src.CategoryName,
        tgt.Description   = src.Description,
        tgt.LoadTimestamp = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (CategoryID, CategoryName, Description)
    VALUES
        (src.CategoryID, src.CategoryName, src.Description);
    SET @total += @@ROWCOUNT;

    -- =========================================================
    -- DimSupplier — MERGE simples (29 linhas)
    -- =========================================================
    MERGE gold.DimSupplier AS tgt
    USING (
        SELECT SupplierID, CompanyName, City, Country
        FROM bronze.Suppliers
    ) AS src ON tgt.SupplierID = src.SupplierID
    WHEN MATCHED THEN UPDATE SET
        tgt.CompanyName   = src.CompanyName,
        tgt.City          = src.City,
        tgt.Country       = src.Country,
        tgt.LoadTimestamp = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (SupplierID, CompanyName, City, Country)
    VALUES
        (src.SupplierID, src.CompanyName, src.City, src.Country);
    SET @total += @@ROWCOUNT;

    -- =========================================================
    -- DimShipper — MERGE simples (3 linhas)
    -- =========================================================
    MERGE gold.DimShipper AS tgt
    USING (
        SELECT ShipperID, CompanyName, Phone
        FROM bronze.Shippers
    ) AS src ON tgt.ShipperID = src.ShipperID
    WHEN MATCHED THEN UPDATE SET
        tgt.CompanyName   = src.CompanyName,
        tgt.Phone         = src.Phone,
        tgt.LoadTimestamp = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (ShipperID, CompanyName, Phone)
    VALUES
        (src.ShipperID, src.CompanyName, src.Phone);
    SET @total += @@ROWCOUNT;

    -- =========================================================
    -- DimTerritory — MERGE com join em Region para RegionName
    -- =========================================================
    MERGE gold.DimTerritory AS tgt
    USING (
        SELECT
            t.TerritoryID,
            t.TerritoryDescription,
            t.RegionID,
            r.RegionDescription AS RegionName
        FROM bronze.Territories t
        LEFT JOIN bronze.Region r ON t.RegionID = r.RegionID
    ) AS src ON tgt.TerritoryID = src.TerritoryID
    WHEN MATCHED THEN UPDATE SET
        tgt.TerritoryDescription = src.TerritoryDescription,
        tgt.RegionID             = src.RegionID,
        tgt.RegionName           = src.RegionName,
        tgt.LoadTimestamp        = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (TerritoryID, TerritoryDescription, RegionID, RegionName)
    VALUES
        (src.TerritoryID, src.TerritoryDescription, src.RegionID, src.RegionName);
    SET @total += @@ROWCOUNT;

    -- =========================================================
    -- DimDate — gera serie 1990-01-01 ate 2030-12-31 (se vazia)
    -- =========================================================
    IF NOT EXISTS (SELECT 1 FROM gold.DimDate)
    BEGIN
        WITH dates AS (
            SELECT CAST('1990-01-01' AS DATE) AS d
            UNION ALL
            SELECT DATEADD(day, 1, d)
            FROM dates
            WHERE d < '2030-12-31'
        )
        INSERT INTO gold.DimDate
            (DateKey, FullDate, Year, Quarter, Month, MonthName,
             Day, DayOfWeek, DayName, IsWeekend)
        SELECT
            CAST(FORMAT(d, 'yyyyMMdd') AS INT)  AS DateKey,
            d                                   AS FullDate,
            YEAR(d)                             AS Year,
            DATEPART(QUARTER, d)                AS Quarter,
            MONTH(d)                            AS Month,
            DATENAME(MONTH, d)                  AS MonthName,
            DAY(d)                              AS Day,
            DATEPART(WEEKDAY, d)                AS DayOfWeek,
            DATENAME(WEEKDAY, d)                AS DayName,
            CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END AS IsWeekend
        FROM dates
        OPTION (MAXRECURSION 15000);

        PRINT 'DimDate populada: 1990-01-01 a 2030-12-31';
    END

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.sp_process_dims', GETDATE(), @total, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.sp_process_dims', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- ---- fonte: construcao/04_gold_scd2.sql ----
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

-- ---- fonte: construcao/05_gold_fact_sales.sql ----
-- ============================================================
-- 05_gold_fact_sales.sql
-- Procedure: gold.sp_process_fact_sales
-- Tecnica: MERGE — evita duplicatas, join com dimensoes via natural key
-- Grain: uma linha por (OrderID, ProductID)
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_sales
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

    MERGE gold.FactSales AS tgt
    USING (
        SELECT
            -- DateKey
            CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)  AS OrderDateKey,
            -- Surrogate keys
            dc.CustomerSK,
            dp.ProductSK,
            de.EmployeeSK,
            ds.ShipperSK,
            -- Natural keys (para deduplicacao)
            od.OrderID,
            od.ProductID,
            -- Metricas
            od.UnitPrice,
            od.Quantity,
            CAST(od.Discount AS DECIMAL(5,4))             AS Discount,
            od.UnitPrice * od.Quantity                    AS GrossRevenue,
            CAST(
                od.UnitPrice * od.Quantity * (1.0 - od.Discount)
            AS DECIMAL(12,2))                             AS NetRevenue
        FROM bronze.OrderDetails od
        JOIN bronze.Orders o
            ON o.OrderID = od.OrderID
        -- CustomerSK: versao vigente na data do pedido
        JOIN gold.DimCustomer dc
            ON dc.CustomerID = o.CustomerID
           AND CAST(o.OrderDate AS DATE) >= dc.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dc.ValidTo
        -- ProductSK: versao vigente na data do pedido
        JOIN gold.DimProduct dp
            ON dp.ProductID = od.ProductID
           AND CAST(o.OrderDate AS DATE) >= dp.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dp.ValidTo
        JOIN gold.DimEmployee de
            ON de.EmployeeID = o.EmployeeID
        JOIN gold.DimShipper ds
            ON ds.ShipperID = o.ShipVia
    ) AS src 
		ON tgt.OrderID = src.OrderID AND tgt.ProductID = src.ProductID

    WHEN MATCHED THEN UPDATE SET
        tgt.OrderDateKey  = src.OrderDateKey,
        tgt.CustomerSK    = src.CustomerSK,
        tgt.ProductSK     = src.ProductSK,
        tgt.EmployeeSK    = src.EmployeeSK,
        tgt.ShipperSK     = src.ShipperSK,
        tgt.UnitPrice     = src.UnitPrice,
        tgt.Quantity      = src.Quantity,
        tgt.Discount      = src.Discount,
        tgt.GrossRevenue  = src.GrossRevenue,
        tgt.NetRevenue    = src.NetRevenue,
        tgt.LoadTimestamp = GETDATE()

    WHEN NOT MATCHED BY TARGET THEN INSERT (
        OrderDateKey, CustomerSK, ProductSK, EmployeeSK, ShipperSK,
        OrderID, ProductID,
        UnitPrice, Quantity, Discount, GrossRevenue, NetRevenue, LoadTimestamp
    ) VALUES (
        src.OrderDateKey, src.CustomerSK, src.ProductSK, src.EmployeeSK, src.ShipperSK,
        src.OrderID, src.ProductID,
        src.UnitPrice, src.Quantity, src.Discount, src.GrossRevenue, src.NetRevenue,
        GETDATE()
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactSales', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactSales', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- ---- fonte: construcao/06_gold_fact_fulfillment.sql ----
-- ============================================================
-- 06_gold_fact_fulfillment.sql
-- Procedure: gold.sp_process_fact_fulfillment
-- Tecnica: Accumulating Snapshot — MERGE que:
--   INSERT novos pedidos
--   UPDATE pedidos existentes quando ShippedDate chega
-- Grain: uma linha por OrderID
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_fulfillment
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

    MERGE gold.FactOrderFulfillment AS tgt
    USING (
        SELECT
            o.OrderID,
            -- CustomerSK: versao vigente na data do pedido
            dc.CustomerSK,
            de.EmployeeSK,
            -- ShipperSK pode ser NULL se ShipVia for NULL
            ds.ShipperSK,
            -- DateKeys: converter datetime -> INT YYYYMMDD
            CAST(FORMAT(o.OrderDate,    'yyyyMMdd') AS INT) AS OrderDateKey,
            CAST(FORMAT(o.RequiredDate, 'yyyyMMdd') AS INT) AS RequiredDateKey,
            -- ShippedDateKey: NULL se ainda nao enviado
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN CAST(FORMAT(o.ShippedDate, 'yyyyMMdd') AS INT)
                 ELSE NULL END                              AS ShippedDateKey,
            o.Freight,
            o.ShipCountry,
            -- DaysToShip: NULL ate envio
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN DATEDIFF(day, o.OrderDate, o.ShippedDate)
                 ELSE NULL END                              AS DaysToShip,
            -- IsLate: NULL ate envio; 1 se atrasou, 0 se no prazo
            CASE WHEN o.ShippedDate IS NOT NULL
                 THEN CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END
                 ELSE NULL END                              AS IsLate
        FROM bronze.Orders o
        -- CustomerSK: versao valida na data do pedido
        JOIN gold.DimCustomer dc
            ON dc.CustomerID = o.CustomerID
           AND CAST(o.OrderDate AS DATE) >= dc.ValidFrom
           AND CAST(o.OrderDate AS DATE) <  dc.ValidTo
        JOIN gold.DimEmployee de
            ON de.EmployeeID = o.EmployeeID
        LEFT JOIN gold.DimShipper ds
            ON ds.ShipperID = o.ShipVia
    ) AS src ON tgt.OrderID = src.OrderID

    -- Pedido ja existe: atualizar apenas se ShippedDate chegou ou mudou
    WHEN MATCHED AND (
        -- Comparacao NULL-safe compativel com SQL Server 2017+
        -- ISNULL(col, sentinela) garante que NULL = NULL nao dispara UPDATE
        ISNULL(tgt.ShippedDateKey, -1)      <> ISNULL(src.ShippedDateKey, -1) OR
        ISNULL(tgt.DaysToShip, -999)        <> ISNULL(src.DaysToShip, -999)   OR
        ISNULL(CAST(tgt.IsLate AS INT), -1) <> ISNULL(CAST(src.IsLate AS INT), -1)
    ) THEN UPDATE SET
        tgt.ShippedDateKey = src.ShippedDateKey,
        tgt.DaysToShip     = src.DaysToShip,
        tgt.IsLate         = src.IsLate,
        tgt.LoadTimestamp  = GETDATE()

    -- Pedido novo: inserir
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        OrderID, CustomerSK, EmployeeSK, ShipperSK,
        OrderDateKey, RequiredDateKey, ShippedDateKey,
        Freight, ShipCountry, DaysToShip, IsLate, LoadTimestamp
    ) VALUES (
        src.OrderID, src.CustomerSK, src.EmployeeSK, src.ShipperSK,
        src.OrderDateKey, src.RequiredDateKey, src.ShippedDateKey,
        src.Freight, src.ShipCountry, src.DaysToShip, src.IsLate,
        GETDATE()
    );

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactOrderFulfillment', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactOrderFulfillment', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO


-- ---- fonte: construcao/07_gold_fact_stock.sql ----
-- ============================================================
-- 07_gold_fact_stock.sql
-- Procedure: gold.sp_process_fact_stock
-- Tecnica: Periodic Snapshot — INSERT do estado atual de Products
-- Cada execucao adiciona uma nova linha por produto (nao faz UPDATE)
-- Grain: (ProductSK, SnapshotDateKey)
-- ============================================================

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_fact_stock
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @snapshotDateKey INT =
        CAST(FORMAT(GETDATE(), 'yyyyMMdd') AS INT);

    -- Nao inserir se ja existe snapshot de hoje
    IF EXISTS (
        SELECT 1 FROM gold.FactProductStock
        WHERE SnapshotDateKey = @snapshotDateKey
    )
    BEGIN
        PRINT 'Snapshot de hoje (' + CAST(@snapshotDateKey AS VARCHAR) + ') ja existe. Nenhuma acao.';
        RETURN;
    END;

    BEGIN TRY

    INSERT INTO gold.FactProductStock
        (SnapshotDateKey, ProductSK, CategorySK,
         UnitsInStock, UnitsOnOrder, ReorderLevel, NeedsReorder, LoadTimestamp)
    SELECT
        @snapshotDateKey,
        dp.ProductSK,
        dc.CategorySK,
        p.UnitsInStock,
        p.UnitsOnOrder,
        p.ReorderLevel,
        CASE WHEN p.UnitsInStock <= p.ReorderLevel THEN 1 ELSE 0 END AS NeedsReorder,
        GETDATE()
    FROM bronze.Products p
    JOIN gold.DimProduct dp
        ON dp.ProductID = p.ProductID AND dp.IsCurrent = 1
    JOIN gold.DimCategory dc
        ON dc.CategoryID = p.CategoryID;

    INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status)
    VALUES ('gold.FactProductStock', GETDATE(), @@ROWCOUNT, 'OK');

    END TRY
    BEGIN CATCH
        INSERT INTO control.pipeline_log (StepName, EndTime, RowsAffected, Status, Message)
        VALUES ('gold.FactProductStock', GETDATE(), 0, 'ERROR', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- ---- fonte: construcao/10_bridge_table.sql ----
-- =============================================================
-- 10_bridge_table.sql
-- Padrao: Bridge Table (Kimball M:N)
-- Contexto: Employee <-> Territory e uma relacao M:N.
-- STRING_AGG em DimEmployee e conveniente mas nao permite
-- analise por territorio. A Bridge resolve isso corretamente.
--
-- So define a procedure. Execucao e exploracao:
-- sql_server/labs/10_bridge_table_lab.sql
-- =============================================================

USE NorthwindDW;
GO

-- Procedure: gold.sp_process_bridge_employee_territory
CREATE OR ALTER PROCEDURE gold.sp_process_bridge_employee_territory
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE gold.BridgeEmployeeTerritory;

    INSERT INTO gold.BridgeEmployeeTerritory (EmployeeSK, TerritorySK)
    SELECT DISTINCT
        de.EmployeeSK,
        dt.TerritorySK
    FROM bronze.EmployeeTerritories et
    JOIN gold.DimEmployee  de ON de.EmployeeID  = et.EmployeeID
    JOIN gold.DimTerritory dt ON dt.TerritoryID = et.TerritoryID;

    DECLARE @rows INT = @@ROWCOUNT;
    INSERT INTO control.pipeline_log (StepName, RowsAffected)
    VALUES ('bridge_employee_territory', @rows);

    PRINT 'Bridge carregada: ' + CAST(@rows AS VARCHAR) + ' linhas.';
END;
GO

-- ---- fonte: construcao/12_scd3.sql ----
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

-- ---- fonte: construcao/13_factless_fact.sql ----
-- =============================================================
-- 13_factless_fact.sql
-- Padrao: Factless Fact Table
-- Contexto: FactEmployeeTerritoryActivity registra EVENTOS
-- sem metricas: um empregado processou pedido(s) em um dia,
-- estando associado a determinados territorios via bridge.
-- Grain: (ActivityDateKey, EmployeeSK, TerritorySK) unico
--
-- So define a procedure. Execucao e exploracao:
-- sql_server/labs/13_factless_fact_lab.sql
-- =============================================================
-- DEPENDENCIA: a procedure de 10_bridge_table.sql precisa ja ter
-- sido executada (gold.BridgeEmployeeTerritory populada).

USE NorthwindDW;
GO

CREATE OR ALTER PROCEDURE gold.sp_process_factless_activity
AS
BEGIN
    SET NOCOUNT ON;

    -- Carga full (idempotente via MERGE)
    MERGE gold.FactEmployeeTerritoryActivity AS tgt
    USING (
        SELECT DISTINCT
            CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)  AS ActivityDateKey,
            de.EmployeeSK,
            b.TerritorySK
        FROM bronze.Orders o
        JOIN gold.DimEmployee              de ON de.EmployeeID = o.EmployeeID
        JOIN gold.BridgeEmployeeTerritory  b  ON b.EmployeeSK = de.EmployeeSK
        JOIN gold.DimDate                  dd ON dd.DateKey    =
             CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)
    ) AS src
    ON  tgt.ActivityDateKey = src.ActivityDateKey
    AND tgt.EmployeeSK      = src.EmployeeSK
    AND tgt.TerritorySK     = src.TerritorySK
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ActivityDateKey, EmployeeSK, TerritorySK)
        VALUES (src.ActivityDateKey, src.EmployeeSK, src.TerritorySK);

    PRINT 'FactEmployeeTerritoryActivity: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas inseridas.';
END;
GO

-- ============================================================
-- Sequência de EXEC — constrói o modelo gold de ponta a ponta
-- ============================================================

USE NorthwindDW;
GO

-- Bronze
-- Procedure definida acima (fonte: construcao/02_bronze_ingest.sql)
EXEC bronze.sp_ingest_bronze;
GO

-- Gold — Dimensões SCD1 + DimDate
-- Procedure definida acima (fonte: construcao/03_gold_dims.sql)
EXEC gold.sp_process_dims;
GO

-- Gold — DimCustomer (SCD2)
-- Procedure definida acima (fonte: construcao/04_gold_scd2.sql)
EXEC gold.sp_process_customers_scd2;
GO

-- Gold — DimProduct (SCD2)
-- Procedure definida acima (fonte: construcao/04_gold_scd2.sql)
EXEC gold.sp_process_products_scd2;
GO

-- FactSales (transacional)
-- Procedure definida acima (fonte: construcao/05_gold_fact_sales.sql)
EXEC gold.sp_process_fact_sales;
GO

-- FactOrderFulfillment (accumulating snapshot)
-- Procedure definida acima (fonte: construcao/06_gold_fact_fulfillment.sql)
EXEC gold.sp_process_fact_fulfillment;
GO

-- FactProductStock (periodic snapshot)
-- Procedure definida acima (fonte: construcao/07_gold_fact_stock.sql)
EXEC gold.sp_process_fact_stock;
GO

-- BridgeEmployeeTerritory (M:N Employee <-> Territory)
-- Procedure definida acima (fonte: construcao/10_bridge_table.sql)
EXEC gold.sp_process_bridge_employee_territory;
GO

-- DimOrderFlags (Junk Dimension) — conteúdo integral inline,
-- fonte: construcao/11_junk_dimension.sql (não usa procedure)

-- =============================================================
-- 11_junk_dimension.sql
-- Padrao: Junk Dimension
-- Contexto: DimOrderFlags agrupa atributos de baixa cardinalidade
-- que descrevem o contexto de cada linha de venda.
-- - DiscountBand: derivado do Discount real do Order Details
-- - IsHighValue: NetRevenue > 1000 (limiar de negocio)
-- - ShipmentMode: mapeado deterministicamente por ShipperID
--   (Northwind nao tem campo, mas o padrao e demonstrado)
--
-- Este arquivo ja executa (nao e so definicao de procedure).
-- Exploracao: sql_server/labs/11_junk_dimension_lab.sql
-- =============================================================

USE NorthwindDW;
GO

-- Passo 1: Popular todas as 24 combinacoes possiveis (4x2x3)
TRUNCATE TABLE gold.DimOrderFlags;

WITH combos AS (
    SELECT d.DiscountBand, v.IsHighValue, s.ShipmentMode
    FROM (VALUES ('None'), ('Low'), ('Medium'), ('High')) AS d(DiscountBand)
    CROSS JOIN (VALUES (CAST(0 AS BIT)), (CAST(1 AS BIT))) AS v(IsHighValue)
    CROSS JOIN (VALUES ('Express'), ('Standard'), ('Economy')) AS s(ShipmentMode)
)
INSERT INTO gold.DimOrderFlags (DiscountBand, IsHighValue, ShipmentMode)
SELECT DiscountBand, IsHighValue, ShipmentMode FROM combos;
GO

-- Passo 2: Popular OrderFlagsSK no FactSales existente
UPDATE fs
SET fs.OrderFlagsSK = dof.OrderFlagsSK
FROM gold.FactSales fs
JOIN bronze.Orders o ON o.OrderID = fs.OrderID
JOIN gold.DimOrderFlags dof
    ON dof.DiscountBand = CASE
           WHEN fs.Discount = 0          THEN 'None'
           WHEN fs.Discount <= 0.05      THEN 'Low'
           WHEN fs.Discount <= 0.15      THEN 'Medium'
           ELSE                               'High'
       END
    AND dof.IsHighValue = CASE
           WHEN fs.NetRevenue > 1000     THEN CAST(1 AS BIT)
           ELSE                               CAST(0 AS BIT)
       END
    AND dof.ShipmentMode = CASE o.ShipVia
           WHEN 1 THEN 'Express'    -- Speedy Express
           WHEN 2 THEN 'Standard'   -- United Package
           ELSE        'Economy'    -- Federal Shipping
       END;
GO

PRINT 'FactSales.OrderFlagsSK populado: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas.';
GO

-- Passo 3: Procedure para carga incremental (novos pedidos)
CREATE OR ALTER PROCEDURE gold.sp_process_junk_dimension
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE fs
    SET fs.OrderFlagsSK = dof.OrderFlagsSK
    FROM gold.FactSales fs
    JOIN bronze.Orders o ON o.OrderID = fs.OrderID
    JOIN gold.DimOrderFlags dof
        ON dof.DiscountBand = CASE
               WHEN fs.Discount = 0          THEN 'None'
               WHEN fs.Discount <= 0.05      THEN 'Low'
               WHEN fs.Discount <= 0.15      THEN 'Medium'
               ELSE                               'High'
           END
        AND dof.IsHighValue = CASE
               WHEN fs.NetRevenue > 1000 THEN CAST(1 AS BIT)
               ELSE                           CAST(0 AS BIT)
           END
        AND dof.ShipmentMode = CASE o.ShipVia
               WHEN 1 THEN 'Express'
               WHEN 2 THEN 'Standard'
               ELSE        'Economy'
           END
    WHERE fs.OrderFlagsSK IS NULL;

    PRINT 'Junk dimension atualizada: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' linhas.';
END;
GO

-- DimCustomerSCD3 — carga inicial
-- Procedure definida acima (fonte: construcao/12_scd3.sql)
EXEC gold.sp_load_customer_scd3_initial;
GO

-- DimCustomerSCD3 — atualização incremental
-- Procedure definida acima (fonte: construcao/12_scd3.sql)
EXEC gold.sp_process_customer_scd3;
GO

-- FactEmployeeTerritoryActivity (Factless Fact)
-- Procedure definida acima (fonte: construcao/13_factless_fact.sql)
EXEC gold.sp_process_factless_activity;
GO

-- ============================================================
-- Resultado: contagem de linhas por tabela
-- ============================================================

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
GO
