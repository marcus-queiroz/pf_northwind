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
