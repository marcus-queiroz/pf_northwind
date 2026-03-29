# T04 — Gold: Fato Transacional (FactSales)

**Frente:** Gold — FactSales
**Implementação:** `sql_server/05_gold_fact_sales.sql` | `spark/05_gold_fact_sales.ipynb` | `duckdb/05_gold_fact_sales.ipynb`

---

## Objetivos

- Entender o padrão de fato transacional (Kimball Cap. 4)
- Aprender a definir grain corretamente
- Calcular métricas derivadas: GrossRevenue, NetRevenue, Discount
- Fazer JOIN com dimensões SCD2 por range de datas

---

## 1. Conceito — Fato Transacional

### O que é

Registra eventos discretos que acontecem em um ponto no tempo. Cada linha representa uma transação atômica — algo que ocorreu e não muda depois.

**Características:**
- Imutável após a inserção
- Cresce continuamente com novos eventos
- Métrica típica: valor monetário, quantidade, contagem

### Os três tipos de fato (Kimball)

| Tipo | Linhas | Atualizável? | Exemplo |
|---|---|---|---|
| **Transacional** | 1 por evento | Não | Venda, clique, transação bancária |
| Accumulating Snapshot | 1 por processo | Sim | Pedido (milestones) |
| Periodic Snapshot | 1 por (entidade × período) | Não (append) | Estoque diário |

### Grain

Definição explícita do que **uma linha representa**. Deve ser declarado antes de definir as colunas.

- Grain muito alto (ex: pedido inteiro) → perde detalhe de produto
- Grain muito baixo (ex: timestamp de cada keystroke) → tabela impraticável

> **Regra:** o grain mais atômico que faz sentido para as perguntas de negócio.

### Tipos de métricas

| Tipo | Definição | Exemplo |
|---|---|---|
| **Aditiva** | Pode somar em todas as dimensões | GrossRevenue, Quantity |
| **Semi-aditiva** | Pode somar em algumas dimensões | Saldo bancário (não soma por tempo) |
| **Não-aditiva** | Não faz sentido somar diretamente | Percentual de desconto |

---

## 2. Mecânica

```sql
INSERT INTO gold.FactSales (CustomerSK, ProductSK, OrderDateKey, ..., GrossRevenue, NetRevenue, Discount)
SELECT
    dc.CustomerSK,
    dp.ProductSK,
    CAST(FORMAT(o.OrderDate, 'yyyyMMdd') AS INT)  AS OrderDateKey,
    od.UnitPrice * od.Quantity                    AS GrossRevenue,
    od.UnitPrice * od.Quantity * (1 - od.Discount) AS NetRevenue,
    od.Discount
FROM bronze.OrderDetails od
JOIN bronze.Orders o         ON od.OrderID = o.OrderID
JOIN silver.DimCustomer dc   ON o.CustomerID = dc.CustomerID AND dc.IsCurrent = 1
JOIN silver.DimProduct  dp   ON od.ProductID = dp.ProductID
                            AND o.OrderDate BETWEEN dp.ValidFrom AND dp.ValidTo
JOIN silver.DimEmployee de   ON o.EmployeeID = de.EmployeeID
JOIN silver.DimShipper  ds   ON o.ShipVia    = ds.ShipperID;
```

Usar MERGE (não INSERT simples) para evitar duplicatas no reprocessamento.

---

## 3. No Northwind

### Grain

**Uma linha por `(OrderID, ProductID)`** — equivalente a uma linha de `bronze.OrderDetails`.

Northwind tem **2.155 linhas** em OrderDetails → FactSales deve ter exatamente **2.155 linhas**.

### Métricas

| Métrica | Cálculo | Tipo |
|---|---|---|
| `GrossRevenue` | `UnitPrice × Quantity` | Aditiva |
| `NetRevenue` | `UnitPrice × Quantity × (1 - Discount)` | Aditiva |
| `Discount` | Campo REAL (0.0–1.0; ex: 0.10 = 10%) | Não-aditiva |
| `Quantity` | `Quantity` | Aditiva |

`GrossRevenue - NetRevenue` = valor monetário do desconto concedido.

`Discount` não deve ser somado diretamente — use `AVG(Discount)` ou analise como `SUM(GrossRevenue - NetRevenue)`.

### Chaves estrangeiras

| FK | Origem | Nota |
|---|---|---|
| CustomerSK | `Orders.CustomerID` → DimCustomer | `IsCurrent=1` (simplificado) ou range de datas |
| ProductSK | `OrderDetails.ProductID` → DimProduct | Range de datas obrigatório (SCD2) |
| EmployeeSK | `Orders.EmployeeID` → DimEmployee | JOIN direto (SCD1) |
| ShipperSK | `Orders.ShipVia` → DimShipper | JOIN direto (SCD1) |
| OrderDateKey | `Orders.OrderDate` | `FORMAT(date, 'yyyyMMdd')::INT` |

### JOIN com DimProduct por range de datas

FactSales captura o atributo vigente **na data do pedido**, não o atual:

```sql
-- CORRETO: produto com preço vigente quando o pedido foi feito
JOIN silver.DimProduct dp
  ON od.ProductID = dp.ProductID
 AND o.OrderDate BETWEEN dp.ValidFrom AND dp.ValidTo

-- SIMPLIFICADO (funciona só se os dados históricos de SCD2 não existirem)
JOIN silver.DimProduct dp
  ON od.ProductID = dp.ProductID AND dp.IsCurrent = 1
```

Procedure: `gold.sp_process_fact_sales`

---

## 4. Implementação por Tecnologia

### SQL Server

```sql
MERGE gold.FactSales AS t
USING (
    SELECT od.OrderID, od.ProductID, dc.CustomerSK, dp.ProductSK, de.EmployeeSK,
           ds.ShipperSK, CAST(FORMAT(o.OrderDate,'yyyyMMdd') AS INT) AS OrderDateKey,
           od.UnitPrice * od.Quantity               AS GrossRevenue,
           od.UnitPrice * od.Quantity * (1-od.Discount) AS NetRevenue,
           od.Discount, od.Quantity
    FROM bronze.OrderDetails od
    JOIN bronze.Orders o        ON od.OrderID   = o.OrderID
    JOIN silver.DimCustomer dc  ON o.CustomerID = dc.CustomerID AND dc.IsCurrent = 1
    JOIN silver.DimProduct dp   ON od.ProductID = dp.ProductID
                               AND o.OrderDate BETWEEN dp.ValidFrom AND dp.ValidTo
    JOIN silver.DimEmployee de  ON o.EmployeeID = de.EmployeeID
    JOIN silver.DimShipper ds   ON o.ShipVia    = ds.ShipperID
) AS s ON t.OrderID = s.OrderID AND t.ProductID = s.ProductID
WHEN NOT MATCHED THEN INSERT (...) VALUES (...);
```

### Spark (PySpark)

```python
from pyspark.sql import functions as F

fact = order_details \
    .join(orders, "OrderID") \
    .join(dim_customer.filter("IsCurrent = 1"), on="CustomerID") \
    .join(dim_product,
          (F.col("od.ProductID") == F.col("dp.ProductID")) &
          (F.col("OrderDate") >= F.col("dp.ValidFrom")) &
          (F.col("OrderDate") <= F.col("dp.ValidTo"))) \
    .withColumn("GrossRevenue", F.col("UnitPrice") * F.col("Quantity")) \
    .withColumn("NetRevenue",
                F.col("UnitPrice") * F.col("Quantity") * (1 - F.col("Discount"))) \
    .withColumn("OrderDateKey",
                F.date_format("OrderDate", "yyyyMMdd").cast("int"))

DeltaTable.forName(spark, "gold.fact_sales") \
    .alias("t").merge(fact.alias("s"),
                      "t.OrderID = s.OrderID AND t.ProductID = s.ProductID") \
    .whenNotMatchedInsertAll().execute()
```

### DuckDB

```sql
INSERT INTO gold.fact_sales
SELECT od.OrderID, od.ProductID,
       dc.CustomerSK, dp.ProductSK, de.EmployeeSK, ds.ShipperSK,
       CAST(strftime('%Y%m%d', o.OrderDate) AS INTEGER) AS OrderDateKey,
       od.UnitPrice * od.Quantity                       AS GrossRevenue,
       od.UnitPrice * od.Quantity * (1 - od.Discount)   AS NetRevenue,
       od.Discount, od.Quantity
FROM bronze.order_details od
JOIN bronze.orders o         ON od.OrderID   = o.OrderID
JOIN silver.dim_customer dc  ON o.CustomerID = dc.CustomerID AND dc.IsCurrent = TRUE
JOIN silver.dim_product dp   ON od.ProductID = dp.ProductID
                            AND o.OrderDate BETWEEN dp.ValidFrom AND dp.ValidTo
JOIN silver.dim_employee de  ON o.EmployeeID = de.EmployeeID
JOIN silver.dim_shipper  ds  ON o.ShipVia    = ds.ShipperID
WHERE NOT EXISTS (
    SELECT 1 FROM gold.fact_sales f
    WHERE f.OrderID = od.OrderID AND f.ProductID = od.ProductID
);
```

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| Grain errado (nível de pedido) | Agregar OrderDetails antes de inserir | Inserir no grain atômico; agregar na query analítica |
| Órfãos na FK | Produto sem versão SCD2 para a data | `LEFT JOIN` + verificar órfãos no lab |
| `Discount` somado diretamente | Não é aditivo | Calcular `SUM(GrossRevenue - NetRevenue)` |
| Reprocessamento gera duplicatas | `INSERT` sem MERGE/dedup | MERGE ou `WHERE NOT EXISTS` |
| `COUNT` ≠ 2.155 | JOIN com multiplicidade errada | Verificar com `COUNT(*)` comparado ao bronze |

---

## 6. Questões de Revisão

1. Qual o grain do FactSales? Por que não usar `OrderID` como grain?
2. Qual a diferença entre GrossRevenue e NetRevenue? Como cada um é calculado?
3. Por que o JOIN com DimProduct usa range de datas em vez de `IsCurrent = 1`?
4. `Discount` é uma métrica aditiva? Como analisá-la corretamente?
5. FactSales tem 2.200 linhas após o processamento (deveria ter 2.155). O que pode ter dado errado?

---

**Sessão anterior:** [T03 — Silver: SCD Tipo 2](T03_scd2.md)
**Próxima sessão:** [T05 — Gold: Accumulating Snapshot](T05_accumulating_snapshot.md)
