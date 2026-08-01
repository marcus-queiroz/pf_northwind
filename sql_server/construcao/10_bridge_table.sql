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
