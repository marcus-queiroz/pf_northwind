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
