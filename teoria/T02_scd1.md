# T02 — Silver: Dimensões SCD Tipo 1

**Frente:** Silver — Dimensões Estáveis
**Implementação:** `sql_server/03_silver_dims.sql` | `spark/03_silver_dims.ipynb` | `duckdb/03_silver_dims.ipynb`

---

## Objetivos

- Entender o conceito de Slowly Changing Dimension e os tipos principais
- Aprender quando aplicar SCD Tipo 1 (sobrescrever sem histórico)
- Dominar o padrão MERGE para upsert de dimensões estáveis
- Compreender surrogate key e por que ela existe

---

## 1. Conceito — SCD e Surrogate Key

### O que é Slowly Changing Dimension

Dimensões descrevem "quem", "o que", "onde" dos fatos. Na prática, esses atributos mudam com o tempo — cliente muda de cidade, produto muda de fornecedor. O termo SCD descreve a estratégia para lidar com essa mudança.

### Tipos principais

| Tipo | O que faz | Histórico | Complexidade |
|---|---|---|---|
| **SCD 1** | Sobrescreve o valor antigo | Perdido | Baixa |
| **SCD 2** | Cria nova versão, preserva a antiga | Preservado | Média |
| SCD 3 | Guarda valor anterior em coluna extra | Parcial (1 versão) | Média |
| SCD 4 | Tabela de histórico separada | Preservado | Alta |

**Quando usar SCD 1:**
Atributos sem valor analítico histórico — correção de typo, atualização de e-mail, campos de referência estáveis. O valor antigo não importa.

**Quando usar SCD 2:**
Atributos cujo valor histórico tem significado analítico — "qual era a cidade do cliente quando ele fez o pedido?". Ver sessão [T03](T03_scd2.md).

### Surrogate Key (SK)

Chave numérica gerada pelo DW, separada da natural key (NK) que vem do OLTP.

**Por que usar SK:**
- Desacopla o DW de mudanças no OLTP (rekeys, merges de sistemas)
- Permite SCD2: dois registros do mesmo NK têm SKs diferentes
- Melhora performance de JOIN (inteiro vs. string)
- Uniformiza o modelo: toda dimensão tem uma PK inteira

No Northwind:
- `DimEmployee.EmployeeSK` = SK gerada | `EmployeeID` = NK
- `DimCategory.CategorySK` = SK gerada | `CategoryID` = NK

---

## 2. Mecânica — MERGE (Upsert)

```sql
MERGE target AS t
USING source AS s ON t.NaturalKey = s.NaturalKey
WHEN MATCHED AND (atributos mudaram)
    THEN UPDATE SET t.col1 = s.col1, t.col2 = s.col2
WHEN NOT MATCHED
    THEN INSERT (NaturalKey, col1, col2) VALUES (s.NaturalKey, s.col1, s.col2);
```

**Resultado por cenário:**

| Situação | Ação |
|---|---|
| NK existe na fonte mas não na dimensão | INSERT |
| NK existe nos dois e atributos diferem | UPDATE |
| NK existe nos dois e atributos iguais | Nenhuma ação (eficiente) |
| NK existe na dimensão mas não na fonte | Nenhuma ação (sem DELETE) |

> Em T-SQL, o `MERGE` exige `;` no final — sintaxe obrigatória, diferente de outros statements.

---

## 3. No Northwind

### Dimensões SCD1 do projeto

| Dimensão | NK | Atributos rastreados | Destaque |
|---|---|---|---|
| DimEmployee | EmployeeID | Title, City, Country, ManagerName, TerritoryList | Self-join + STRING_AGG |
| DimCategory | CategoryID | CategoryName, Description | MERGE simples (8 linhas) |
| DimSupplier | SupplierID | CompanyName, Country, City | MERGE simples (29 linhas) |
| DimShipper | ShipperID | CompanyName, Phone | MERGE simples (3 linhas) |
| DimTerritory | TerritoryID | TerritoryDescription, RegionName | Join com Region |
| DimDate | DateKey | Year, Month, Quarter, DayOfWeek... | Gerada por série — não por MERGE |

### Destaque: DimEmployee com hierarquia achatada

Employee tem auto-relacionamento via `ReportsTo`. Em vez de expor isso no DW — o que obrigaria JOINs recursivos em toda query analítica —, a hierarquia é achatada na procedure:

```sql
SELECT
    e.EmployeeID,
    e.FirstName + ' ' + e.LastName          AS FullName,
    m.FirstName + ' ' + m.LastName          AS ManagerName,    -- self-join
    STRING_AGG(t.TerritoryDescription, ', ')
        WITHIN GROUP (ORDER BY t.TerritoryDescription)         -- M:N achatado
        AS TerritoryList,
    r.RegionDescription                      AS RegionName
FROM bronze.Employees e
LEFT JOIN bronze.Employees m          ON e.ReportsTo = m.EmployeeID
LEFT JOIN bronze.EmployeeTerritories et ON e.EmployeeID = et.EmployeeID
LEFT JOIN bronze.Territories t        ON et.TerritoryID = t.TerritoryID
LEFT JOIN bronze.Region r             ON t.RegionID = r.RegionID
GROUP BY e.EmployeeID, e.FirstName, e.LastName, e.Title, e.HireDate,
         e.City, e.Country, e.ReportsTo, m.FirstName, m.LastName,
         r.RegionDescription
```

Isso demonstra leitura do modelo OLTP e decisão consciente de design dimensional (Kimball: hierarquias fixas devem ser achatadas quando possível).

### DimDate

Não vem do OLTP — é gerada diretamente no DW por uma série de datas (1990–2030). O range amplo cobre `HireDate`/`BirthDate` dos funcionários (anos 1940+) e qualquer pedido futuro.

```sql
-- Geração de série (SQL Server)
WITH dates AS (
    SELECT CAST('1990-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(day, 1, d) FROM dates WHERE d < '2030-12-31'
)
INSERT INTO silver.DimDate (DateKey, FullDate, Year, Month, Quarter, ...)
SELECT FORMAT(d, 'yyyyMMdd'), d, YEAR(d), MONTH(d), DATEPART(QUARTER, d), ...
FROM dates
OPTION (MAXRECURSION 0);
```

Procedure: `silver.sp_process_dims`

---

## 4. Implementação por Tecnologia

### SQL Server

```sql
MERGE silver.DimCategory AS t
USING (
    SELECT CategoryID, CategoryName, Description FROM bronze.Categories
) AS s ON t.CategoryID = s.CategoryID
WHEN MATCHED AND (
    t.CategoryName  <> s.CategoryName OR
    ISNULL(t.Description, '') <> ISNULL(s.Description, '')
)
    THEN UPDATE SET
        t.CategoryName  = s.CategoryName,
        t.Description   = s.Description
WHEN NOT MATCHED
    THEN INSERT (CategoryID, CategoryName, Description)
         VALUES (s.CategoryID, s.CategoryName, s.Description);
-- Atenção: ';' obrigatório após MERGE em T-SQL
```

### Spark (PySpark)

```python
from delta.tables import DeltaTable

delta_table = DeltaTable.forName(spark, "silver.dim_category")
delta_table.alias("t") \
    .merge(source_df.alias("s"), "t.CategoryID = s.CategoryID") \
    .whenMatchedUpdateAll() \
    .whenNotMatchedInsertAll() \
    .execute()
```

SK para SCD1: `F.abs(F.hash("CategoryID"))` — determinístico entre execuções.

### DuckDB

```sql
INSERT OR REPLACE INTO silver.dim_category (CategorySK, CategoryID, CategoryName)
SELECT
    CAST(hash(CategoryID) % 2147483647 AS INTEGER) AS CategorySK,
    CategoryID,
    CategoryName
FROM bronze.categories;
```

`INSERT OR REPLACE` exige `UNIQUE` constraint na natural key (`CategoryID`). Múltiplas `UNIQUE` constraints em colunas diferentes causam erro de ambiguidade no DuckDB 0.10 → definir `UNIQUE` apenas na NK, nunca no SK.

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| `MERGE` sem `;` final | Sintaxe obrigatória em T-SQL | Sempre terminar com `;` |
| `ORDER BY` em view sem `TOP/OFFSET` | SQL Server não permite | Mover `ORDER BY` para a query chamadora |
| `STRING_AGG` sem GROUP BY completo | Colunas não-agregadas fora do GROUP BY | Incluir todas as colunas não-agregadas |
| `INSERT OR REPLACE` com 2 `UNIQUE` | DuckDB não sabe qual usar para o REPLACE | `UNIQUE` apenas na NK |
| DimDate reinserida a cada execução | INSERT sem verificar existência | `IF NOT EXISTS (SELECT 1 FROM silver.DimDate)` |

---

## 6. Questões de Revisão

1. Qual a diferença entre SCD Tipo 1 e Tipo 2? Quando você escolheria cada um?
2. Por que usar surrogate key em vez da chave natural do OLTP?
3. No DimEmployee, por que achatar a hierarquia em vez de expor o campo `ReportsTo`?
4. O que acontece com um registro de DimEmployee se o funcionário muda de cidade e você
   re-executa `sp_process_dims`? E se fosse SCD2?
5. Por que DimDate é gerada por série em vez de extraída do OLTP?

---

**Sessão anterior:** [T01 — Bronze: Ingestão Full Load](T01_bronze_ingestion.md)
**Próxima sessão:** [T03 — Silver: Dimensões SCD Tipo 2](T03_scd2.md)
