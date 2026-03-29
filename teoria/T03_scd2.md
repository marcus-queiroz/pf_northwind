# T03 — Silver: Dimensões SCD Tipo 2

**Frente:** Silver — Dimensões com Histórico
**Implementação:** `sql_server/04_silver_scd2.sql` | `spark/04_silver_scd2.ipynb` | `duckdb/04_silver_scd2.ipynb`

---

## Objetivos

- Entender como preservar histórico com ValidFrom/ValidTo/IsCurrent
- Implementar o padrão de expiração + inserção
- Compreender por que `ValidFrom='1900-01-01'` é crítico na carga inicial
- Saber fazer JOIN com fatos usando range de datas vs. IsCurrent

---

## 1. Conceito — SCD Tipo 2

### O que é

Quando um atributo muda, o registro antigo é **expirado** (ValidTo recebe a data de ontem, IsCurrent = 0) e um novo registro é **inserido** com os novos valores (ValidFrom = hoje, ValidTo = '9999-12-31', IsCurrent = 1).

- **Pro:** histórico completo preservado — dá para saber qual era o valor em qualquer data
- **Contra:** tabela cresce com o tempo; JOINs com fatos exigem atenção extra
- **Quando usar:** atributos cujo valor histórico tem significado analítico

### Colunas de controle

| Coluna | Tipo | Significado |
|---|---|---|
| `ValidFrom` | DATE | Início da validade desta versão |
| `ValidTo` | DATE | Fim da validade (`9999-12-31` = versão atual) |
| `IsCurrent` | BIT | `1` se é a versão ativa hoje |

### Como fazer JOIN com fatos

Duas abordagens, com propósitos diferentes:

```sql
-- Abordagem 1: atributo vigente NA DATA DO FATO (correto para análise histórica)
-- "Qual era a cidade do cliente quando ele fez o pedido?"
JOIN silver.DimCustomer dc
  ON f.CustomerID = dc.CustomerID
 AND f.OrderDate BETWEEN dc.ValidFrom AND dc.ValidTo

-- Abordagem 2: atributo ATUAL (útil para relatórios do estado hoje)
-- "Qual a cidade atual dos nossos top 10 clientes?"
JOIN silver.DimCustomer dc
  ON f.CustomerID = dc.CustomerID
 AND dc.IsCurrent = 1
```

---

## 2. Mecânica — Expirar + Inserir

```
1. Detectar mudanças
   SELECT CustomerID FROM bronze.Customers + DimCustomer (IsCurrent=1)
   WHERE atributos divergem

2. Expirar versão atual
   UPDATE DimCustomer
   SET ValidTo = ontem, IsCurrent = 0
   WHERE CustomerID IN (lista) AND IsCurrent = 1

3. Inserir nova versão
   INSERT INTO DimCustomer (..., ValidFrom, ValidTo, IsCurrent)
   SELECT ..., hoje, '9999-12-31', 1
   FROM bronze.Customers WHERE CustomerID IN (lista)

4. Inserir registros novos (que não existiam)
   INSERT INTO DimCustomer
   SELECT ... FROM bronze.Customers
   WHERE CustomerID NOT IN (SELECT CustomerID FROM DimCustomer)
```

---

## 3. No Northwind

### Dimensões SCD2 do projeto

| Dimensão | NK | Atributos rastreados | Motivação |
|---|---|---|---|
| DimCustomer | CustomerID | ContactName, ContactTitle, City, Country | Comportamento geográfico ao longo do tempo |
| DimProduct | ProductID | UnitPrice, Discontinued | Catálogo histórico; Order Details grava o preço cobrado, mas o SCD2 preserva a evolução do catálogo |

### Por que `ValidFrom = '1900-01-01'` na carga inicial

Os pedidos do Northwind são de **1996–1998**. Se a carga inicial usar `GETDATE()` como ValidFrom, o JOIN temporal falha para todos os pedidos históricos (`OrderDate < ValidFrom`).

```sql
-- ERRADO: pedidos de 1996 ficam sem dimensão
INSERT INTO silver.DimCustomer (..., ValidFrom)
VALUES (..., GETDATE())  -- ValidFrom = 2026-03-xx

-- CORRETO: todos os pedidos históricos encontram uma versão válida
INSERT INTO silver.DimCustomer (..., ValidFrom)
VALUES (..., '1900-01-01')
```

> **Regra geral:** na carga inicial de SCD2, sempre usar "começo dos tempos" como ValidFrom.

### DimProduct — desnormalização

DimProduct desnormaliza `CategoryName` (join bronze.Categories) e `SupplierCompany` (join bronze.Suppliers) diretamente na dimensão. Isso evita JOINs extras ao consultar FactSales.

Decisão consciente: no modelo dimensional (Kimball), desnormalizar dimensões é esperado e desejável. A tabela de fatos deve ser simples — poucos joins, métricas claras.

Procedures: `silver.sp_process_customers_scd2`, `silver.sp_process_products_scd2`

---

## 4. Implementação por Tecnologia

### SQL Server

```sql
-- Expirar versões antigas
UPDATE silver.DimCustomer
SET ValidTo   = DATEADD(day, -1, CAST(GETDATE() AS DATE)),
    IsCurrent = 0
WHERE CustomerID IN (SELECT CustomerID FROM #mudancas)
  AND IsCurrent = 1;

-- Inserir nova versão
INSERT INTO silver.DimCustomer
    (CustomerID, CompanyName, ContactName, City, Country, ValidFrom, ValidTo, IsCurrent)
SELECT CustomerID, CompanyName, ContactName, City, Country,
       CAST(GETDATE() AS DATE), '9999-12-31', 1
FROM bronze.Customers
WHERE CustomerID IN (SELECT CustomerID FROM #mudancas);
```

Comparação NULL-safe: usar `ISNULL(col, '')` ou `IS DISTINCT FROM` (SQL Server 2022+).

### Spark (PySpark)

```python
from delta.tables import DeltaTable

delta = DeltaTable.forName(spark, "silver.dim_customer")

# Expirar versões antigas
delta.update(
    condition=f"CustomerID IN ({changed_ids}) AND IsCurrent = 1",
    set={
        "ValidTo":    "date_sub(current_date(), 1)",
        "IsCurrent":  "0"
    }
)

# Inserir novas versões (append)
new_versions.write.format("delta").mode("append").saveAsTable("silver.dim_customer")
```

SK para SCD2: `F.abs(F.hash("CustomerID", "ValidFrom"))` — inclui ValidFrom para garantir SK diferente entre versões do mesmo NK.

### DuckDB

```python
# Expirar
conn.execute(f"""
    UPDATE silver.dim_customer
    SET ValidTo   = current_date - INTERVAL '1 day',
        IsCurrent = FALSE
    WHERE IsCurrent = TRUE
      AND CustomerID IN ({id_list})
""")

# Nova versão
conn.execute(f"""
    INSERT INTO silver.dim_customer
    SELECT CAST(hash(CustomerID || '{today}') % 2147483647 AS INTEGER),
           CustomerID, CompanyName, ContactName, City, Country,
           DATE '{today}', DATE '9999-12-31', TRUE
    FROM bronze.customers
    WHERE CustomerID IN ({id_list})
""")
```

> **Bug DuckDB 0.10:** `UPDATE ... RETURNING` com `UNIQUE` constraint gera "Duplicate key" (UPDATE faz delete+insert internamente e o check falha). Fix: remover `RETURNING`, medir impacto com `COUNT(*)` antes/depois.

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| `ValidFrom = GETDATE()` na carga inicial | Fatos históricos ficam fora do range | Usar `'1900-01-01'` na carga inicial |
| Comparação com `NULL` usando `<>` | `NULL <> 'x'` retorna `NULL`, não `TRUE` | `ISNULL()` ou `IS DISTINCT FROM` |
| `UPDATE...RETURNING` falha no DuckDB | Bug 0.10 com `UNIQUE` constraint | Remover `RETURNING` |
| JOIN com `IsCurrent=1` em relatório histórico | Retorna atributo atual, não o vigente na data | JOIN por range de datas (`BETWEEN ValidFrom AND ValidTo`) |
| SK idêntico para 2 versões no Spark | Hash só da NK | Incluir `ValidFrom` no hash do SK |

---

## 6. Questões de Revisão

1. Um cliente mudou de cidade em 2020. Como recuperar a cidade dele no momento de um pedido feito em 2019? E em 2021?
2. Por que a carga inicial usa `ValidFrom='1900-01-01'` e não `GETDATE()`?
3. Qual a diferença prática entre filtrar por `IsCurrent=1` vs. filtrar por range de datas?
4. DimProduct denormaliza `CategoryName`. Que problema isso cria se uma categoria muda de nome? Como o SCD2 lida com isso?
5. No Spark, por que o SK de SCD2 inclui `ValidFrom` no hash, diferente do SCD1?

---

**Sessão anterior:** [T02 — Silver: SCD Tipo 1](T02_scd1.md)
**Próxima sessão:** [T04 — Gold: Fato Transacional](T04_fato_transacional.md)
