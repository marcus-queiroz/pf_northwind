# T01 — Bronze: Ingestão Full Load

**Frente:** Camada Bronze do pipeline
**Implementação:** `sql_server/02_bronze_ingest.sql` | `spark/02_bronze_ingest.ipynb` | `duckdb/02_bronze_ingest.ipynb`

---

## Objetivos

- Entender o papel da Bronze na arquitetura Medallion
- Compreender o padrão Full Load (TRUNCATE + INSERT) e suas alternativas
- Identificar decisões de design: o que excluir, o que renomear e por quê

---

## 1. Arquitetura Medallion

O pipeline segue três camadas:

```
OLTP (Northwind)          Bronze                 Silver                Gold
─────────────────         ──────────────         ─────────────────     ──────────────
dbo.Customers        →    bronze.Customers   →   DimCustomer (SCD2)  ↘
dbo.Orders           →    bronze.Orders      →   (joins)              → FactSales
dbo.OrderDetails     →    bronze.OrderDetails     (joins)             ↗
```

**Bronze** é a camada de aterrisagem: cópia fiel da fonte, sem lógica de negócio.
**Silver** transforma e aplica regras (SCD, hierarquias, denormalização).
**Gold** é o modelo dimensional: fatos e dimensões prontos para análise.

### Por que não transformar direto na fonte?

A Bronze serve como **buffer persistente**. Se a Silver falhar, você reprocessa a partir da Bronze sem reconectar à fonte OLTP — que pode estar sob carga, ter cota de leitura, ou ser um sistema externo ao qual você não tem acesso a qualquer momento.

---

## 2. Full Load vs. Alternativas

| Estratégia | Mecânica | Vantagem | Desvantagem | Quando usar |
|---|---|---|---|---|
| **Full Load** | TRUNCATE + INSERT | Simples, sempre correto | Reprocessa tudo | Tabelas pequenas/médias sem campo de controle |
| **Incremental** | INSERT/UPDATE onde `updated_at > último checkpoint` | Eficiente em volume | Depende de coluna confiável | Tabelas grandes com `updated_at` |
| **CDC** | Captura eventos do log da fonte | Latência mínima, captura DELETEs | Infraestrutura complexa | Alta frequência, missão crítica |

**No Northwind usamos Full Load porque:**
- Tabelas pequenas (máx. ~2.000 linhas)
- Fonte é um banco de amostra sem `updated_at` confiável
- Objetivo é portfólio: clareza > otimização prematura

### Mecânica do Full Load

```sql
-- SQL Server
TRUNCATE TABLE bronze.Customers;
INSERT INTO bronze.Customers (CustomerID, CompanyName, ContactName, ...)
SELECT CustomerID, CompanyName, ContactName, ...
FROM dbo.Customers;
```

`TRUNCATE` é preferível a `DELETE` porque não gera log de linha por linha — muito mais rápido em tabelas grandes e reseta o contador de IDENTITY.

---

## 3. No Northwind

### Tabelas ingeridas

| Tabela Bronze | Origem | Linhas |
|---|---|---|
| bronze.Customers | dbo.Customers | 91 |
| bronze.Employees | dbo.Employees | 9 |
| bronze.Products | dbo.Products | 77 |
| bronze.Categories | dbo.Categories | 8 |
| bronze.Suppliers | dbo.Suppliers | 29 |
| bronze.Shippers | dbo.Shippers | 3 |
| bronze.Orders | dbo.Orders | 830 |
| bronze.OrderDetails | dbo.[Order Details] | 2.155 |
| bronze.Territories | dbo.Territories | 53 |
| bronze.Region | dbo.Region | 4 |
| bronze.EmployeeTerritories | dbo.EmployeeTerritories | 49 |

### Decisões de design

**O que renomear:**
`dbo.[Order Details]` (com espaço) → `bronze.OrderDetails`
Espaços em nomes de objetos exigem colchetes em T-SQL e são incompatíveis com convenções de Spark e DuckDB. Renomear na Bronze evita carregar esse problema para todas as camadas seguintes.

**O que excluir:**

| Tabela | Coluna excluída | Motivo |
|---|---|---|
| Employees | `Photo` | BLOB (`image`); sem valor analítico; incompatível com CSV |
| Categories | `Picture` | BLOB (`image`) |
| Suppliers | `HomePage` | URL de texto longo sem uso analítico |

> **Princípio:** a Bronze deve ser a cópia mais fiel possível da fonte, com apenas os ajustes mínimos necessários para viabilizar o processamento nas camadas seguintes.

---

## 4. Implementação por Tecnologia

### SQL Server

Procedure `bronze.sp_ingest_bronze` executa 11 pares de TRUNCATE + INSERT em sequência:

```sql
CREATE OR ALTER PROCEDURE bronze.sp_ingest_bronze AS
BEGIN
    TRUNCATE TABLE bronze.Customers;
    INSERT INTO bronze.Customers (CustomerID, CompanyName, ContactName, City, Country)
    SELECT CustomerID, CompanyName, ContactName, City, Country
    FROM dbo.Customers;

    TRUNCATE TABLE bronze.OrderDetails;
    INSERT INTO bronze.OrderDetails (OrderID, ProductID, UnitPrice, Quantity, Discount)
    SELECT OrderID, ProductID, UnitPrice, Quantity, Discount
    FROM dbo.[Order Details];   -- colchetes necessários apenas na fonte
    -- ... (11 tabelas no total)
END
```

### Spark (PySpark)

```python
df = spark.read.csv("data/customers.csv", header=True, inferSchema=True)
df.write.format("delta").mode("overwrite").saveAsTable("bronze.customers")
# mode("overwrite") é o equivalente semântico do TRUNCATE + INSERT
```

Cuidado com `employees.csv`: tem quebras de linha (`\n`) em campos de endereço.
Sem `.option("multiLine", True)`, o Spark infere `EmployeeID` como `STRING` em vez de `INT`, quebrando o MERGE do DimEmployee silenciosamente.

```python
df_emp = spark.read.csv("data/employees.csv", header=True, inferSchema=True,
                         multiLine=True)  # obrigatório
```

### DuckDB

```python
conn.execute("""
    INSERT INTO bronze.customers
    SELECT * FROM read_csv_auto('data/customers.csv', header=true)
""")
# Sempre passar header=true no DuckDB 0.10 — sem isso, o header vira dado
```

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| Header incluído como dado | `read_csv_auto` sem `header=true` (DuckDB 0.10) | Sempre passar `header=true` explicitamente |
| Dados multiline quebram inferência | `employees.csv` tem `\n` em endereços | Spark: `.option("multiLine", True)` |
| `TRUNCATE` falha com FK | Bronze não deve ter FK entre tabelas | Não criar FK na camada Bronze |
| Colunas BLOB causam erro de export | `varbinary`/`image` não serializável em CSV | Excluir na query de export, não no schema |
| `SELECT INTO` copia IDENTITY | `SELECT col INTO nova FROM src` copia IDENTITY | Usar `CAST(col AS INT)` para remover |

---

**Próxima sessão:** [T02 — Silver: Dimensões SCD Tipo 1](T02_scd1.md)
