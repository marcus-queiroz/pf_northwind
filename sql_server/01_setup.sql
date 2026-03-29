-- ============================================================
-- 01_setup.sql
-- Cria o banco NorthwindDW com schemas e todas as tabelas
-- bronze / silver / gold / control
-- ============================================================

-- Passo 1: dropar se estiver registrado (re-execucao limpa)
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NorthwindDW')
BEGIN
    ALTER DATABASE NorthwindDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NorthwindDW;
    PRINT 'Banco NorthwindDW anterior removido.';
END
GO

-- Criar banco limpo
-- Se ocorrer "Cannot create file NorthwindDW.mdf because it already exists":
--   o arquivo fisico ficou orfao de uma execucao anterior. Delete o .mdf e .ldf
--   manualmente em /var/opt/mssql/data/ (Docker) ou no diretorio de dados do SQL Server.
CREATE DATABASE NorthwindDW;
PRINT 'Banco NorthwindDW criado.';
GO

USE NorthwindDW;
GO

-- ============================================================
-- SCHEMAS
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'control')
    EXEC('CREATE SCHEMA control');
GO

-- ============================================================
-- BRONZE — copias fieis do dbo.* com _LoadTimestamp
-- ============================================================

-- Limpar tabelas existentes (re-execucao segura)
IF OBJECT_ID('bronze.EmployeeTerritories') IS NOT NULL DROP TABLE bronze.EmployeeTerritories;
IF OBJECT_ID('bronze.Territories')         IS NOT NULL DROP TABLE bronze.Territories;
IF OBJECT_ID('bronze.Region')              IS NOT NULL DROP TABLE bronze.Region;
IF OBJECT_ID('bronze.OrderDetails')        IS NOT NULL DROP TABLE bronze.OrderDetails;
IF OBJECT_ID('bronze.Orders')              IS NOT NULL DROP TABLE bronze.Orders;
IF OBJECT_ID('bronze.Shippers')            IS NOT NULL DROP TABLE bronze.Shippers;
IF OBJECT_ID('bronze.Suppliers')           IS NOT NULL DROP TABLE bronze.Suppliers;
IF OBJECT_ID('bronze.Categories')          IS NOT NULL DROP TABLE bronze.Categories;
IF OBJECT_ID('bronze.Products')            IS NOT NULL DROP TABLE bronze.Products;
IF OBJECT_ID('bronze.Employees')           IS NOT NULL DROP TABLE bronze.Employees;
IF OBJECT_ID('bronze.Customers')           IS NOT NULL DROP TABLE bronze.Customers;
GO

CREATE TABLE bronze.Customers (
    CustomerID      NCHAR(5)     NOT NULL,
    CompanyName     VARCHAR(40)  NOT NULL,
    ContactName     VARCHAR(30)  NULL,
    ContactTitle    VARCHAR(30)  NULL,
    Address         VARCHAR(60)  NULL,
    City            VARCHAR(15)  NULL,
    Region          VARCHAR(15)  NULL,
    PostalCode      VARCHAR(10)  NULL,
    Country         VARCHAR(15)  NULL,
    Phone           VARCHAR(24)  NULL,
    Fax             VARCHAR(24)  NULL,
    _LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Employees (
    EmployeeID       INT          NOT NULL,
    LastName         VARCHAR(20)  NOT NULL,
    FirstName        VARCHAR(10)  NOT NULL,
    Title            VARCHAR(30)  NULL,
    TitleOfCourtesy  VARCHAR(25)  NULL,
    BirthDate        DATETIME     NULL,
    HireDate         DATETIME     NULL,
    Address          VARCHAR(60)  NULL,
    City             VARCHAR(15)  NULL,
    Region           VARCHAR(15)  NULL,
    PostalCode       VARCHAR(10)  NULL,
    Country          VARCHAR(15)  NULL,
    HomePhone        VARCHAR(24)  NULL,
    Extension        VARCHAR(4)   NULL,
    ReportsTo        INT          NULL,
    PhotoPath        VARCHAR(255) NULL,
    _LoadTimestamp   DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Products (
    ProductID        INT            NOT NULL,
    ProductName      VARCHAR(40)    NOT NULL,
    SupplierID       INT            NULL,
    CategoryID       INT            NULL,
    QuantityPerUnit  VARCHAR(20)    NULL,
    UnitPrice        DECIMAL(10,2)  NULL,
    UnitsInStock     SMALLINT       NULL,
    UnitsOnOrder     SMALLINT       NULL,
    ReorderLevel     SMALLINT       NULL,
    Discontinued     BIT            NOT NULL,
    _LoadTimestamp   DATETIME       NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Categories (
    CategoryID      INT          NOT NULL,
    CategoryName    VARCHAR(15)  NOT NULL,
    Description     VARCHAR(200) NULL,
    _LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Suppliers (
    SupplierID      INT          NOT NULL,
    CompanyName     VARCHAR(40)  NOT NULL,
    ContactName     VARCHAR(30)  NULL,
    ContactTitle    VARCHAR(30)  NULL,
    Address         VARCHAR(60)  NULL,
    City            VARCHAR(15)  NULL,
    Region          VARCHAR(15)  NULL,
    PostalCode      VARCHAR(10)  NULL,
    Country         VARCHAR(15)  NULL,
    Phone           VARCHAR(24)  NULL,
    Fax             VARCHAR(24)  NULL,
    _LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Shippers (
    ShipperID       INT          NOT NULL,
    CompanyName     VARCHAR(40)  NOT NULL,
    Phone           VARCHAR(24)  NULL,
    _LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Orders (
    OrderID         INT            NOT NULL,
    CustomerID      NCHAR(5)       NULL,
    EmployeeID      INT            NULL,
    OrderDate       DATETIME       NULL,
    RequiredDate    DATETIME       NULL,
    ShippedDate     DATETIME       NULL,
    ShipVia         INT            NULL,
    Freight         DECIMAL(10,2)  NULL,
    ShipName        VARCHAR(40)    NULL,
    ShipAddress     VARCHAR(60)    NULL,
    ShipCity        VARCHAR(15)    NULL,
    ShipRegion      VARCHAR(15)    NULL,
    ShipPostalCode  VARCHAR(10)    NULL,
    ShipCountry     VARCHAR(15)    NULL,
    _LoadTimestamp  DATETIME       NOT NULL DEFAULT GETDATE()
);
GO

-- Nota: [Order Details] renomeado para OrderDetails (sem espaco)
CREATE TABLE bronze.OrderDetails (
    OrderID         INT            NOT NULL,
    ProductID       INT            NOT NULL,
    UnitPrice       DECIMAL(10,2)  NOT NULL,
    Quantity        SMALLINT       NOT NULL,
    Discount        REAL           NOT NULL,
    _LoadTimestamp  DATETIME       NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Territories (
    TerritoryID          VARCHAR(20)  NOT NULL,
    TerritoryDescription VARCHAR(50)  NOT NULL,
    RegionID             INT          NOT NULL,
    _LoadTimestamp       DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.Region (
    RegionID          INT          NOT NULL,
    RegionDescription VARCHAR(50)  NOT NULL,
    _LoadTimestamp    DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

CREATE TABLE bronze.EmployeeTerritories (
    EmployeeID      INT          NOT NULL,
    TerritoryID     VARCHAR(20)  NOT NULL,
    _LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO

-- ============================================================
-- SILVER — Dimensoes
-- ============================================================

IF OBJECT_ID('gold.DimDate')                IS NOT NULL DROP TABLE gold.DimDate;
IF OBJECT_ID('gold.BridgeEmployeeTerritory') IS NOT NULL DROP TABLE gold.BridgeEmployeeTerritory;
IF OBJECT_ID('gold.DimCustomerSCD3')         IS NOT NULL DROP TABLE gold.DimCustomerSCD3;
IF OBJECT_ID('gold.DimOrderFlags')           IS NOT NULL DROP TABLE gold.DimOrderFlags;
IF OBJECT_ID('gold.DimTerritory')            IS NOT NULL DROP TABLE gold.DimTerritory;
IF OBJECT_ID('gold.DimShipper')              IS NOT NULL DROP TABLE gold.DimShipper;
IF OBJECT_ID('gold.DimSupplier')             IS NOT NULL DROP TABLE gold.DimSupplier;
IF OBJECT_ID('gold.DimCategory')             IS NOT NULL DROP TABLE gold.DimCategory;
IF OBJECT_ID('gold.DimProduct')              IS NOT NULL DROP TABLE gold.DimProduct;
IF OBJECT_ID('gold.DimEmployee')             IS NOT NULL DROP TABLE gold.DimEmployee;
IF OBJECT_ID('gold.DimCustomer')             IS NOT NULL DROP TABLE gold.DimCustomer;
GO

CREATE TABLE gold.DimCustomer (
    CustomerSK    INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CustomerID    NCHAR(5)      NOT NULL,
    CompanyName   VARCHAR(40)   NOT NULL,
    ContactName   VARCHAR(30)   NULL,
    ContactTitle  VARCHAR(30)   NULL,
    City          VARCHAR(15)   NULL,
    Country       VARCHAR(15)   NULL,
    ValidFrom     DATE          NOT NULL,
    ValidTo       DATE          NOT NULL DEFAULT '9999-12-31',
    IsCurrent     BIT           NOT NULL DEFAULT 1
);
GO
CREATE INDEX IX_DimCustomer_NK ON gold.DimCustomer (CustomerID, IsCurrent);
GO

CREATE TABLE gold.DimEmployee (
    EmployeeSK     INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    EmployeeID     INT          NOT NULL,
    FullName       VARCHAR(35)  NOT NULL,
    Title          VARCHAR(30)  NULL,
    HireDate       DATE         NULL,
    City           VARCHAR(15)  NULL,
    Country        VARCHAR(15)  NULL,
    ReportsToID    INT          NULL,
    ManagerName    VARCHAR(35)  NULL,
    TerritoryList  VARCHAR(500) NULL,
    RegionName     VARCHAR(50)  NULL,
    LoadTimestamp  DATETIME     NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_DimEmployee ON gold.DimEmployee (EmployeeID);
GO

CREATE TABLE gold.DimProduct (
    ProductSK        INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ProductID        INT           NOT NULL,
    ProductName      VARCHAR(40)   NOT NULL,
    CategoryName     VARCHAR(15)   NULL,
    SupplierCompany  VARCHAR(40)   NULL,
    UnitPrice        DECIMAL(10,2) NULL,
    QuantityPerUnit  VARCHAR(20)   NULL,
    Discontinued     BIT           NOT NULL DEFAULT 0,
    ValidFrom        DATE          NOT NULL,
    ValidTo          DATE          NOT NULL DEFAULT '9999-12-31',
    IsCurrent        BIT           NOT NULL DEFAULT 1
);
GO
CREATE INDEX IX_DimProduct_NK ON gold.DimProduct (ProductID, IsCurrent);
GO

CREATE TABLE gold.DimCategory (
    CategorySK    INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CategoryID    INT          NOT NULL,
    CategoryName  VARCHAR(15)  NOT NULL,
    Description   VARCHAR(200) NULL,
    LoadTimestamp DATETIME     NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_DimCategory ON gold.DimCategory (CategoryID);
GO

CREATE TABLE gold.DimSupplier (
    SupplierSK    INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    SupplierID    INT          NOT NULL,
    CompanyName   VARCHAR(40)  NOT NULL,
    City          VARCHAR(15)  NULL,
    Country       VARCHAR(15)  NULL,
    LoadTimestamp DATETIME     NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_DimSupplier ON gold.DimSupplier (SupplierID);
GO

CREATE TABLE gold.DimShipper (
    ShipperSK     INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ShipperID     INT          NOT NULL,
    CompanyName   VARCHAR(40)  NOT NULL,
    Phone         VARCHAR(24)  NULL,
    LoadTimestamp DATETIME     NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_DimShipper ON gold.DimShipper (ShipperID);
GO

CREATE TABLE gold.DimTerritory (
    TerritorySK          INT         NOT NULL IDENTITY(1,1) PRIMARY KEY,
    TerritoryID          VARCHAR(20) NOT NULL,
    TerritoryDescription VARCHAR(50) NOT NULL,
    RegionID             INT         NOT NULL,
    RegionName           VARCHAR(50) NULL,
    LoadTimestamp        DATETIME    NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_DimTerritory ON gold.DimTerritory (TerritoryID);
GO

-- ============================================================
-- SILVER: Bridge Table (M:N Employee <-> Territory)
-- ============================================================
CREATE TABLE gold.BridgeEmployeeTerritory (
    EmployeeSK  INT NOT NULL,
    TerritorySK INT NOT NULL,
    CONSTRAINT PK_BridgeEmployeeTerritory PRIMARY KEY (EmployeeSK, TerritorySK)
);
GO

-- ============================================================
-- SILVER: Junk Dimension (flags do FactSales)
-- ============================================================
CREATE TABLE gold.DimOrderFlags (
    OrderFlagsSK INT      IDENTITY(1,1)  PRIMARY KEY,
    DiscountBand NVARCHAR(10) NOT NULL,   -- 'None','Low','Medium','High'
    IsHighValue  BIT          NOT NULL,   -- NetRevenue > 1000
    ShipmentMode NVARCHAR(10) NOT NULL,   -- 'Express','Standard','Economy'
    CONSTRAINT UQ_DimOrderFlags UNIQUE (DiscountBand, IsHighValue, ShipmentMode)
);
GO

-- ============================================================
-- SILVER: DimCustomerSCD3 (historico limitado — tabela separada)
-- ============================================================
CREATE TABLE gold.DimCustomerSCD3 (
    CustomerID       NCHAR(5)      NOT NULL PRIMARY KEY,
    CompanyName      NVARCHAR(40)  NOT NULL,
    ContactName      NVARCHAR(30)  NULL,
    CurrentCity      NVARCHAR(15)  NULL,
    PreviousCity     NVARCHAR(15)  NULL,   -- NULL enquanto nunca mudou
    CityChangedOn    DATE          NULL,   -- NULL enquanto nunca mudou
    CurrentCountry   NVARCHAR(15)  NULL,
    PreviousCountry  NVARCHAR(15)  NULL,
    CountryChangedOn DATE          NULL,
    LoadTimestamp    DATETIME      DEFAULT GETDATE()
);
GO

CREATE TABLE gold.DimDate (
    DateKey    INT         NOT NULL PRIMARY KEY,  -- YYYYMMDD
    FullDate   DATE        NOT NULL,
    Year       SMALLINT    NOT NULL,
    Quarter    TINYINT     NOT NULL,
    Month      TINYINT     NOT NULL,
    MonthName  VARCHAR(10) NOT NULL,
    Day        TINYINT     NOT NULL,
    DayOfWeek  TINYINT     NOT NULL,
    DayName    VARCHAR(10) NOT NULL,
    IsWeekend  BIT         NOT NULL
);
GO

-- ============================================================
-- GOLD — Fatos
-- ============================================================

IF OBJECT_ID('gold.FactEmployeeTerritoryActivity') IS NOT NULL DROP TABLE gold.FactEmployeeTerritoryActivity;
IF OBJECT_ID('gold.FactProductStock')              IS NOT NULL DROP TABLE gold.FactProductStock;
IF OBJECT_ID('gold.FactOrderFulfillment')          IS NOT NULL DROP TABLE gold.FactOrderFulfillment;
IF OBJECT_ID('gold.FactSales')                     IS NOT NULL DROP TABLE gold.FactSales;
IF OBJECT_ID('gold.v_ShippedDate',  'V')           IS NOT NULL DROP VIEW gold.v_ShippedDate;
IF OBJECT_ID('gold.v_RequiredDate', 'V')           IS NOT NULL DROP VIEW gold.v_RequiredDate;
IF OBJECT_ID('gold.v_OrderDate',    'V')           IS NOT NULL DROP VIEW gold.v_OrderDate;
GO

CREATE TABLE gold.FactSales (
    SalesSK        INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    OrderDateKey   INT            NOT NULL,
    CustomerSK     INT            NOT NULL,
    ProductSK      INT            NOT NULL,
    EmployeeSK     INT            NOT NULL,
    ShipperSK      INT            NOT NULL,
    OrderID        INT            NOT NULL,
    ProductID      INT            NOT NULL,  -- NK para deduplicacao
    UnitPrice      DECIMAL(10,2)  NOT NULL,
    Quantity       SMALLINT       NOT NULL,
    Discount       DECIMAL(5,4)   NOT NULL,
    GrossRevenue   DECIMAL(12,2)  NOT NULL,
    NetRevenue     DECIMAL(12,2)  NOT NULL,
    OrderFlagsSK   INT            NULL,      -- Junk Dimension SK (nullable ate populacao)
    LoadTimestamp  DATETIME       NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_FactSales_Grain ON gold.FactSales (OrderID, ProductID);
GO

CREATE TABLE gold.FactOrderFulfillment (
    FulfillmentSK    INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    OrderID          INT           NOT NULL,  -- NK (grain)
    CustomerSK       INT           NOT NULL,
    EmployeeSK       INT           NOT NULL,
    ShipperSK        INT           NULL,
    OrderDateKey     INT           NOT NULL,
    RequiredDateKey  INT           NOT NULL,
    ShippedDateKey   INT           NULL,
    Freight          DECIMAL(10,2) NULL,
    ShipCountry      VARCHAR(15)   NULL,
    DaysToShip       INT           NULL,
    IsLate           BIT           NULL,
    LoadTimestamp    DATETIME      NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_FactOrderFulfillment_Grain ON gold.FactOrderFulfillment (OrderID);
GO

CREATE TABLE gold.FactProductStock (
    StockSK          INT      NOT NULL IDENTITY(1,1) PRIMARY KEY,
    SnapshotDateKey  INT      NOT NULL,
    ProductSK        INT      NOT NULL,
    CategorySK       INT      NOT NULL,
    UnitsInStock     SMALLINT NOT NULL,
    UnitsOnOrder     SMALLINT NOT NULL,
    ReorderLevel     SMALLINT NOT NULL,
    NeedsReorder     BIT      NOT NULL,
    LoadTimestamp    DATETIME NOT NULL DEFAULT GETDATE()
);
GO
CREATE UNIQUE INDEX UX_FactProductStock_Grain ON gold.FactProductStock (SnapshotDateKey, ProductSK);
GO

-- ============================================================
-- GOLD: Factless Fact Table (Employee x Territory x Date)
-- ============================================================
CREATE TABLE gold.FactEmployeeTerritoryActivity (
    ActivityDateKey INT NOT NULL,
    EmployeeSK      INT NOT NULL,
    TerritorySK     INT NOT NULL,
    CONSTRAINT PK_FactEmployeeTerritoryActivity
        PRIMARY KEY (ActivityDateKey, EmployeeSK, TerritorySK)
);
GO

-- ============================================================
-- GOLD: Role-Playing Views sobre DimDate
-- ============================================================
CREATE VIEW gold.v_OrderDate    AS SELECT * FROM gold.DimDate;
GO
CREATE VIEW gold.v_RequiredDate AS SELECT * FROM gold.DimDate;
GO
CREATE VIEW gold.v_ShippedDate  AS SELECT * FROM gold.DimDate;
GO

-- ============================================================
-- CONTROL
-- ============================================================

IF OBJECT_ID('control.pipeline_log') IS NOT NULL DROP TABLE control.pipeline_log;
GO

CREATE TABLE control.pipeline_log (
    LogID        INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    StepName     VARCHAR(100) NOT NULL,
    StartTime    DATETIME     NOT NULL DEFAULT GETDATE(),
    EndTime      DATETIME     NULL,
    RowsAffected INT          NULL,
    Status       VARCHAR(20)  NULL,
    Message      VARCHAR(500) NULL
);
GO

PRINT 'Setup NorthwindDW concluido.';
PRINT 'Schemas: bronze, silver, gold, control';
PRINT 'Tabelas bronze: 11 | silver: 11 | gold: 4 | control: 1 | views: 3';
GO
