# T06 — Gold: Periodic Snapshot (FactProductStock)

**Frente:** Gold — FactProductStock
**Implementação:** `sql_server/07_gold_fact_stock.sql` | `spark/07_gold_fact_stock.ipynb` | `duckdb/07_gold_fact_stock.ipynb`

---

## Objetivos

- Entender o padrão Periodic Snapshot (Kimball Cap. 5)
- Aprender a diferença entre snapshot e fato transacional
- Implementar a lógica append-only com idempotência
- Usar o snapshot para análise temporal do estoque

---

## 1. Conceito — Periodic Snapshot

### O que é

Registra o **estado de uma entidade em intervalos regulares de tempo** (diário, semanal, mensal). Cada execução **adiciona novas linhas** — nunca atualiza as anteriores.

**Característica central:** captura "fotografia" do estado em um momento. Permite comparar entre períodos: ontem vs. hoje, semana passada vs. esta semana.

Não registra eventos — registra **condição**.

### Comparativo final — os três tipos de fato

| Tipo | Evento ou Estado? | Atualizável? | Grain |
|---|---|---|---|
| Transacional | Evento atômico | Não | 1 por transação |
| Accumulating Snapshot | Estado de um processo | Sim (milestones) | 1 por instância do processo |
| **Periodic Snapshot** | Estado periódico | Não (append) | 1 por (entidade × período) |

### Quando usar

- Entidades sem transação direta visível (estoque não gera evento, apenas existe)
- Necessidade de comparação temporal ("como evoluiu o estoque do produto X nos últimos 30 dias?")
- KPIs periódicos: saldo de conta, nível de estoque, taxa de ocupação

### Idempotência

Uma execução no mesmo dia não deve gerar duplicatas. A solução é verificar se já existe um snapshot para o `SnapshotDateKey` antes de inserir.

---

## 2. Mecânica — Append-only com Idempotência

```sql
DECLARE @hoje INT = CAST(FORMAT(GETDATE(), 'yyyyMMdd') AS INT);

IF NOT EXISTS (SELECT 1 FROM gold.FactProductStock WHERE SnapshotDateKey = @hoje)
BEGIN
    INSERT INTO gold.FactProductStock
        (ProductSK, ProductID, SnapshotDateKey, UnitsInStock, UnitsOnOrder, ReorderLevel, NeedsReorder)
    SELECT
        dp.ProductSK, p.ProductID, @hoje,
        p.UnitsInStock, p.UnitsOnOrder, p.ReorderLevel,
        CASE WHEN p.UnitsInStock <= p.ReorderLevel THEN 1 ELSE 0 END
    FROM bronze.Products p
    JOIN silver.DimProduct dp ON p.ProductID = dp.ProductID AND dp.IsCurrent = 1;
END
```

**Comportamento por execução:**

| Execução | SnapshotDateKey | Ação |
|---|---|---|
| 1ª (dia A) | A | INSERT 77 linhas |
| 2ª (dia B, diferente) | B | INSERT 77 linhas |
| 3ª (dia A de novo) | A | Nenhuma ação (já existe) |

Total após 2 dias distintos: **154 linhas**.

---

## 3. No Northwind

### Grain

**Uma linha por `(ProductID, SnapshotDateKey)`**. Northwind: 77 produtos → 77 linhas por execução.

### Métricas

| Métrica | Cálculo | Significado |
|---|---|---|
| `UnitsInStock` | Campo direto | Estoque disponível |
| `UnitsOnOrder` | Campo direto | Unidades em pedido ao fornecedor |
| `ReorderLevel` | Campo direto | Nível de gatilho de reposição |
| `NeedsReorder` | `UnitsInStock <= ReorderLevel ? 1 : 0` | Flag de reposição necessária |

### Análises possíveis

```sql
-- Produtos que precisam de reposição no snapshot mais recente
SELECT p.ProductName, s.UnitsInStock, s.ReorderLevel
FROM gold.FactProductStock s
JOIN silver.DimProduct p ON s.ProductSK = p.ProductSK AND p.IsCurrent = 1
WHERE s.SnapshotDateKey = (SELECT MAX(SnapshotDateKey) FROM gold.FactProductStock)
  AND s.NeedsReorder = 1
ORDER BY s.UnitsInStock;

-- Evolução do estoque de um produto ao longo do tempo
SELECT s.SnapshotDateKey, s.UnitsInStock, s.NeedsReorder
FROM gold.FactProductStock s
JOIN silver.DimProduct p ON s.ProductSK = p.ProductSK AND p.IsCurrent = 1
WHERE p.ProductName = 'Chai'
ORDER BY s.SnapshotDateKey;

-- Quantos produtos precisavam de reposição há 30 dias
SELECT COUNT(*) AS NeedsReorder30d
FROM gold.FactProductStock
WHERE SnapshotDateKey = (
    SELECT TOP 1 SnapshotDateKey FROM gold.FactProductStock
    WHERE SnapshotDateKey < CAST(FORMAT(DATEADD(day,-30,GETDATE()),'yyyyMMdd') AS INT)
    ORDER BY SnapshotDateKey DESC
)
AND NeedsReorder = 1;
```

Procedure: `gold.sp_process_fact_stock`

---

## 4. Implementação por Tecnologia

### SQL Server

```sql
CREATE OR ALTER PROCEDURE gold.sp_process_fact_stock AS
BEGIN
    DECLARE @hoje INT = CAST(FORMAT(GETDATE(), 'yyyyMMdd') AS INT);

    IF NOT EXISTS (SELECT 1 FROM gold.FactProductStock WHERE SnapshotDateKey = @hoje)
    BEGIN
        INSERT INTO gold.FactProductStock
            (ProductSK, ProductID, SnapshotDateKey,
             UnitsInStock, UnitsOnOrder, ReorderLevel, NeedsReorder)
        SELECT dp.ProductSK, p.ProductID, @hoje,
               p.UnitsInStock, p.UnitsOnOrder, p.ReorderLevel,
               CASE WHEN p.UnitsInStock <= p.ReorderLevel THEN 1 ELSE 0 END
        FROM bronze.Products p
        JOIN silver.DimProduct dp ON p.ProductID = dp.ProductID AND dp.IsCurrent = 1;

        PRINT CAST(@@ROWCOUNT AS VARCHAR) + ' linhas inseridas no snapshot de ' + CAST(@hoje AS VARCHAR);
    END
    ELSE
        PRINT 'Snapshot para ' + CAST(@hoje AS VARCHAR) + ' já existe. Nenhuma ação.';
END
```

### Spark (PySpark)

```python
from datetime import datetime

snapshot_date_key = int(datetime.now().strftime("%Y%m%d"))

# Verificar se já existe
existing = spark.sql(f"""
    SELECT COUNT(*) AS cnt FROM gold.fact_product_stock
    WHERE SnapshotDateKey = {snapshot_date_key}
""").collect()[0]["cnt"]

if existing == 0:
    snapshot_df = products_df \
        .join(dim_product.filter("IsCurrent = 1"), on="ProductID") \
        .withColumn("SnapshotDateKey", F.lit(snapshot_date_key)) \
        .withColumn("NeedsReorder",
                    F.when(F.col("UnitsInStock") <= F.col("ReorderLevel"), 1).otherwise(0))

    snapshot_df.write.format("delta").mode("append").saveAsTable("gold.fact_product_stock")
    print(f"Snapshot {snapshot_date_key}: {snapshot_df.count()} linhas inseridas")
else:
    print(f"Snapshot {snapshot_date_key} já existe.")
```

### DuckDB

```python
snapshot_date_key = int(conn.execute(
    "SELECT CAST(strftime('%Y%m%d', current_date) AS INTEGER)"
).fetchone()[0])

existing = conn.execute(f"""
    SELECT COUNT(*) FROM gold.fact_product_stock
    WHERE SnapshotDateKey = {snapshot_date_key}
""").fetchone()[0]

if existing == 0:
    conn.execute(f"""
        INSERT INTO gold.fact_product_stock
        SELECT dp.ProductSK, p.ProductID, {snapshot_date_key},
               p.UnitsInStock, p.UnitsOnOrder, p.ReorderLevel,
               CASE WHEN p.UnitsInStock <= p.ReorderLevel THEN 1 ELSE 0 END
        FROM bronze.products p
        JOIN silver.dim_product dp ON p.ProductID = dp.ProductID AND dp.IsCurrent = TRUE
    """)
    n = conn.execute(f"""
        SELECT COUNT(*) FROM gold.fact_product_stock
        WHERE SnapshotDateKey = {snapshot_date_key}
    """).fetchone()[0]
    print(f"Snapshot {snapshot_date_key}: {n} linhas inseridas")
else:
    print(f"Snapshot {snapshot_date_key} já existe.")
```

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| Duplicatas ao reprocessar | INSERT sem checar `SnapshotDateKey` | `IF NOT EXISTS` ou `WHERE NOT EXISTS` |
| `NeedsReorder` sempre 0 | `ReorderLevel = 0` em produtos descontinuados | Aceitar o comportamento ou filtrar `Discontinued = 0` |
| Snapshot com dados desatualizados | Bronze não foi recarregada antes | Garantir ordem: Bronze → Silver → Gold no pipeline |
| JOIN com DimProduct retorna múltiplas linhas | Produto com 2 versões SCD2 ativas | Filtrar `IsCurrent = 1` |
| Confundir com Transacional | "Estoque mudou → evento" não é a mesma coisa que "estoque atual" | Periodic Snapshot registra estado, não evento de mudança |

---

**Sessão anterior:** [T05 — Gold: Accumulating Snapshot](T05_accumulating_snapshot.md)

---

## Resumo do Pipeline

```
Bronze        Silver SCD1       Silver SCD2       Gold
──────────    ───────────────   ───────────────   ─────────────────────────
Full Load  →  MERGE (upsert) →  Expirar+Inserir → FactSales (Transacional)
(T01)         (T02)             (T03)             FactOrderFulfillment (Accumulating) (T05)
                                                  FactProductStock (Periodic) (T06)
                                (T04) ─────────── FactSales grain + métricas
```
