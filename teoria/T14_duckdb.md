# T14 — DuckDB

**Frente:** Contextualização da camada tecnológica DuckDB
**Implementação:** `duckdb/` (notebooks 01–14)

---

## Objetivos

- Entender o que é DuckDB e por que ele existe como categoria própria de banco de dados
- Compreender a arquitetura in-process e suas implicações práticas
- Mapear as extensões de SQL usadas no projeto e o que cada uma faz
- Conhecer as peculiaridades da versão 0.10 usadas neste projeto

---

## 1. O Que é DuckDB

### A categoria

Bancos de dados relacionais se dividem historicamente em duas categorias:

| | OLTP (Transacional) | OLAP (Analítico) |
|---|---|---|
| **Foco** | Muitas transações pequenas | Poucas queries grandes |
| **Armazenamento** | Por linha (row-oriented) | Por coluna (columnar) |
| **Exemplos** | PostgreSQL, MySQL, SQL Server | BigQuery, Snowflake, Redshift |

SQLite preenchia o nicho de banco embarcado para OLTP. DuckDB preenche o nicho de banco embarcado para OLAP.

> **Definição simples:** DuckDB é para analytics o que SQLite é para aplicações — um banco de dados completo que roda *dentro do seu processo*, sem servidor separado.

### Por que colunar é mais rápido para analytics

```
Query: SELECT SUM(GrossRevenue) FROM fact_sales WHERE OrderYear = 1997

Row-oriented (SQL Server):      Columnar (DuckDB):
┌─SK─┬─CustSK─┬─Revenue─┐      Lê apenas a coluna Revenue:
│  1 │   12   │  450.00 │      [450.00, 320.00, 180.00, ...]
│  2 │   34   │  320.00 │      → Vetorizado, cache-friendly
│  3 │   12   │  180.00 │      → Compressão melhor por coluna
└────┴────────┴─────────┘
↑ Lê tudo, mesmo sem usar CustSK
```

Para SUM/AVG/GROUP BY em tabelas largas, o banco colunar lê significativamente menos dados.

---

## 2. Arquitetura In-Process

### Sem servidor

Em PostgreSQL ou SQL Server, há um processo servidor separado que recebe conexões de rede:

```
[Python] --TCP/IP--> [SQL Server process] --disk--> [.mdf files]
```

Em DuckDB, o banco *é* uma biblioteca Python:

```
[Python] --function call--> [DuckDB library] --disk--> [.duckdb file]
```

Não há porta, não há autenticação de rede, não há processo separado para gerenciar. O arquivo `.duckdb` é portátil — copie para outro computador e o banco vai junto.

### Conexão no projeto

```python
import duckdb

# Banco persistente em arquivo
conn = duckdb.connect("northwind_dw.duckdb")

# Banco em memória (descartado ao fechar)
conn = duckdb.connect(":memory:")
```

### _SafeProxy — Workaround necessário no DuckDB 0.10

A versão 0.10 tem um bug: `connection.fetchdf()` causa segfault em certos contextos:

```python
# utils.py — wrapper que intercepta fetchdf() e usa fetchall() + pd.DataFrame()
class _SafeProxy:
    def __init__(self, conn):
        self._conn = conn

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def execute(self, query, params=None):
        if params:
            result = self._conn.execute(query, params)
        else:
            result = self._conn.execute(query)
        return _SafeResult(result)

# Uso:
conn = _SafeProxy(duckdb.connect("northwind_dw.duckdb"))
df = conn.execute("SELECT * FROM gold.dim_customer").fetchdf()  # seguro
```

---

## 3. SQL do DuckDB — Extensões Usadas no Projeto

DuckDB usa SQL padrão como base, com várias extensões práticas.

### read_csv_auto() — Ingestão de CSV

```sql
-- Ler CSV diretamente como tabela (sem CREATE TABLE intermediário)
INSERT INTO bronze.customers
SELECT * FROM read_csv_auto('data/customers.csv', header=true);
```

> **Armadilha DuckDB 0.10:** sem `header=true` explícito, a primeira linha (header) vira linha de dado. Sempre passar o parâmetro.

### INSERT OR REPLACE INTO — SCD1

```sql
-- Upsert: se a PK já existe, substitui; se não existe, insere
INSERT OR REPLACE INTO gold.dim_employee
SELECT
    CAST(hash(EmployeeID) % 2147483647 AS INTEGER) AS EmployeeSK,
    EmployeeID,
    FirstName || ' ' || LastName AS FullName,
    ...
FROM bronze.employees;
```

Equivalente semântico ao `MERGE whenMatchedUpdate + whenNotMatchedInsert` do SQL Server, mas mais conciso para SCD1. Requer `UNIQUE` constraint **apenas na natural key** — não no SK (múltiplas UNIQUE constraints causam ambiguidade no OR REPLACE).

### QUALIFY — Filtro de Window Function sem Subquery

```sql
-- Sem QUALIFY: subquery necessária
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY OrderID) AS rn
    FROM fact_order_fulfillment
) WHERE rn = 1;

-- Com QUALIFY: direto
SELECT *
FROM fact_order_fulfillment
QUALIFY ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY OrderID) = 1;
```

`QUALIFY` filtra o resultado de window functions na mesma query, sem subquery. Equivalente ao `HAVING` para agregações, mas para window functions.

### IS DISTINCT FROM — Comparação NULL-safe

```sql
-- Problema: NULL <> NULL retorna NULL (não TRUE)
WHERE City <> src.City  -- falha se City for NULL em algum lado

-- Solução: IS DISTINCT FROM (retorna TRUE se valores são diferentes, incluindo NULL vs não-NULL)
WHERE City IS DISTINCT FROM src.City
   OR Country IS DISTINCT FROM src.Country
```

DuckDB suporta nativamente. Em SQL Server 2017, usar `ISNULL(col, '')` como alternativa.

### generate_series() — DimDate

```sql
INSERT INTO gold.dim_date
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)  AS DateKey,
    d                                        AS FullDate,
    YEAR(d)                                 AS Year,
    MONTH(d)                                AS Month,
    DAY(d)                                  AS Day,
    ...
FROM generate_series(DATE '1990-01-01', DATE '2030-12-31', INTERVAL '1 day') gs(d);
```

Gera uma sequência de datas sem tabela auxiliar. Equivalente ao `ROW_NUMBER()` trick do SQL Server para DimDate.

### hash() — Surrogate Keys Determinísticos

```sql
CAST(hash(CustomerID) % 2147483647 AS INTEGER)  AS CustomerSK
-- Para SCD2 (garante SK único por versão):
CAST(hash(CustomerID || ValidFrom::VARCHAR) % 2147483647 AS INTEGER)  AS CustomerSK
```

`hash()` é uma função built-in que retorna um inteiro de 64 bits. O `% 2147483647` restringe a faixa ao máximo de `INT` (2³¹ - 1). Determinístico: mesma entrada sempre produz mesmo SK.

### PIVOT — Analytics Nativo

```sql
-- Sem PIVOT: CASE WHEN explícito para cada ano
SELECT ProductID,
       SUM(CASE WHEN Year = 1996 THEN NetRevenue END) AS "1996",
       SUM(CASE WHEN Year = 1997 THEN NetRevenue END) AS "1997",
       SUM(CASE WHEN Year = 1998 THEN NetRevenue END) AS "1998"
FROM gold.fact_sales GROUP BY ProductID;

-- Com PIVOT nativo do DuckDB:
PIVOT gold.fact_sales
ON Year
USING SUM(NetRevenue)
GROUP BY ProductID;
```

---

## 4. Diferenças em Relação ao SQL Server

| Funcionalidade | SQL Server | DuckDB |
|---|---|---|
| Upsert | `MERGE ... WHEN MATCHED UPDATE / WHEN NOT MATCHED INSERT` | `INSERT OR REPLACE INTO` |
| Filtro de window | Subquery necessária | `QUALIFY` diretamente |
| Gerar sequência de datas | `ROW_NUMBER()` + `DATEADD` trick | `generate_series()` |
| Pivot | `PIVOT` (sintaxe rígida) ou `CASE WHEN` | `PIVOT ON ... USING SUM(...)` |
| UPDATE com fonte externa | `UPDATE t SET ... FROM src WHERE t.id = src.id` | Idêntico (sem keyword `JOIN`) |
| Procedures | `CREATE PROCEDURE`, `EXEC` | Não tem — lógica fica no Python |
| NULL-safe compare | `ISNULL(a,'') = ISNULL(b,'')` ou `IS DISTINCT FROM` (2022+) | `IS DISTINCT FROM` nativo |
| Surrogate key | `IDENTITY` ou sequence | `hash()` determinístico |
| Concatenar strings | `+` ou `CONCAT()` | `\|\|` ou `CONCAT()` |

---

## 5. Armadilhas DuckDB 0.10

| Armadilha | Causa | Fix |
|-----------|-------|-----|
| Header incluído como dado | `read_csv_auto` infere sem checar explicitamente | Sempre `read_csv_auto('file.csv', header=true)` |
| `fetchdf()` causa segfault | Bug de versão no método Python | Usar `_SafeProxy` de `utils.py` |
| `UPDATE ... RETURNING` com `UNIQUE` falha | DuckDB 0.10 implementa UPDATE como delete+insert; o UNIQUE check falha no insert mesmo sem duplicatas reais | Remover `RETURNING`; medir impacto com `SELECT COUNT(*)` antes/depois |
| Múltiplas UNIQUE constraints com `INSERT OR REPLACE` | O OR REPLACE não sabe qual constraint usar para o "replace" | Definir UNIQUE apenas na natural key, não no SK |

---

## 6. DuckDB vs Spark — Quando Usar Cada Um

| Critério | DuckDB | Spark + Delta Lake |
|---|---|---|
| Volume de dados | Até ~100 GB em um nó | Terabytes em cluster |
| Latência de setup | Instantânea (import + connect) | Minutos (JVM, SparkSession) |
| MERGE/UPDATE complexo | Suporte nativo, sintaxe simples | Via `DeltaTable` API |
| Time Travel | Não suportado nativamente | `DESCRIBE HISTORY`, `VERSION AS OF` |
| Escalabilidade horizontal | Não (single node) | Sim (cluster) |
| Portabilidade | Um arquivo `.duckdb` | Diretório `warehouse/` |
| SQL puro | Quase tudo via SQL | Mix Python + SQL |

> **Contexto do projeto:** os três stacks (SQL Server, Spark, DuckDB) implementam o **mesmo modelo dimensional** com o **mesmo dataset**. DuckDB se destaca pela simplicidade: sem configuração de servidor, sem JVM, sem Delta transaction log — apenas SQL analítico rápido em um arquivo portátil.

---

## 7. Questões de Revisão

1. Por que DuckDB é chamado de banco "analítico embarcado"? O que diferencia de SQLite?
2. O que `QUALIFY ROW_NUMBER() OVER (...) = 1` faz que uma subquery tradicional também faz? Qual a vantagem?
3. Por que `INSERT OR REPLACE INTO` requer `UNIQUE` apenas na natural key, não no surrogate key?
4. `hash(CustomerID) % 2147483647` é determinístico: sempre gera o mesmo SK para o mesmo CustomerID. Qual seria o problema se não fosse determinístico?
5. Em que situação você escolheria DuckDB em vez de Spark para um pipeline de DW?

---

**Sessão anterior:** [T13 — Apache Spark + Delta Lake](T13_spark_delta_lake.md)
