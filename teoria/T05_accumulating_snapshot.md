# T05 — Gold: Accumulating Snapshot (FactOrderFulfillment)

**Frente:** Gold — FactOrderFulfillment
**Implementação:** `sql_server/06_gold_fact_fulfillment.sql` | `spark/06_gold_fact_fulfillment.ipynb` | `duckdb/06_gold_fact_fulfillment.ipynb`

---

## Objetivos

- Entender o padrão Accumulating Snapshot (Kimball Cap. 6)
- Aprender quando usá-lo: processos com milestones definidos
- Implementar o MERGE bidirecional (INSERT novos + UPDATE quando milestone chega)
- Calcular DaysToShip e IsLate

---

## 1. Conceito — Accumulating Snapshot

### O que é

Registra o **estado acumulado de um processo** que passa por etapas conhecidas (milestones). Uma linha por instância do processo. A linha é **atualizada** conforme o processo avança.

Contraste com os outros tipos:

| Tipo | Linhas | Atualizável? | Quando usar |
|---|---|---|---|
| Transacional | 1 por evento atômico | Não | Vendas, cliques, transações |
| **Accumulating Snapshot** | 1 por instância do processo | Sim | Pedidos, contratos, casos de suporte |
| Periodic Snapshot | 1 por (entidade × período) | Não | Saldo, estoque, KPIs periódicos |

### Quando o padrão se aplica

Use Accumulating Snapshot quando o processo tem:
1. Instâncias discretas e identificáveis (ex: um pedido com ID único)
2. Um conjunto **conhecido e fixo** de etapas (milestones)
3. Necessidade de medir duração e performance entre etapas

Se as etapas forem dinâmicas ou ilimitadas, o padrão não se aplica bem.

### Milestones

Datas/eventos que marcam cada etapa do processo. Cada milestone vira uma coluna de data na tabela de fato e uma FK para DimDate.

---

## 2. Mecânica — MERGE Bidirecional

```
Primeira execução (carga inicial):
  Pedidos com ShippedDate → INSERT com todos os milestones preenchidos
  Pedidos sem ShippedDate → INSERT com ShippedDateKey = NULL

Execuções subsequentes:
  Pedidos novos                → INSERT (WHEN NOT MATCHED)
  Pedidos que receberam ShippedDate → UPDATE da linha existente (WHEN MATCHED)
  Pedidos já processados       → nenhuma ação (condição no WHEN MATCHED)
```

```sql
MERGE gold.FactOrderFulfillment AS t
USING (...source...) AS s ON t.OrderID = s.OrderID
WHEN MATCHED
    AND t.ShippedDateKey IS NULL        -- ainda não registrado
    AND s.ShippedDate IS NOT NULL       -- ShippedDate chegou
    THEN UPDATE SET
        t.ShippedDateKey = CAST(FORMAT(s.ShippedDate, 'yyyyMMdd') AS INT),
        t.DaysToShip     = DATEDIFF(day, s.OrderDate, s.ShippedDate),
        t.IsLate         = CASE WHEN s.ShippedDate > s.RequiredDate THEN 1 ELSE 0 END
WHEN NOT MATCHED
    THEN INSERT (...) VALUES (...);
```

A condição dupla no `WHEN MATCHED` garante que o UPDATE **só dispara** quando a ShippedDate chegou e ainda não foi registrada. Evita updates desnecessários em pedidos já processados.

---

## 3. No Northwind

### Grain

**Uma linha por `OrderID`.** O Northwind tem **830 pedidos** → FactOrderFulfillment deve ter **830 linhas**.

### Milestones

| Milestone | Coluna | Quando preenchida |
|---|---|---|
| Pedido feito | `OrderDate` | Sempre (criação do pedido) |
| Prazo prometido | `RequiredDate` | Sempre (criação do pedido) |
| Pedido enviado | `ShippedDate` | Quando despachado — pode ser NULL |

### Métricas derivadas

```sql
DaysToShip = DATEDIFF(day, OrderDate, ShippedDate)   -- NULL se ShippedDate IS NULL
IsLate     = CASE
                 WHEN ShippedDate IS NULL THEN 0      -- ainda pendente
                 WHEN ShippedDate > RequiredDate THEN 1
                 ELSE 0
             END
```

### Perguntas analíticas possíveis

- Qual a performance de entrega por Shipper? (`AVG(DaysToShip)` + `AVG(IsLate)`)
- Quantos pedidos foram entregues com atraso por país de destino?
- Qual o lead time médio por funcionário responsável?
- Quais pedidos ainda estão pendentes (sem ShippedDate)?

Procedure: `gold.sp_process_fact_fulfillment`

---

## 4. Implementação por Tecnologia

### SQL Server

```sql
MERGE gold.FactOrderFulfillment AS t
USING (
    SELECT
        o.OrderID, dc.CustomerSK, de.EmployeeSK, ds.ShipperSK,
        CAST(FORMAT(o.OrderDate,    'yyyyMMdd') AS INT) AS OrderDateKey,
        CAST(FORMAT(o.RequiredDate, 'yyyyMMdd') AS INT) AS RequiredDateKey,
        o.ShippedDate,
        DATEDIFF(day, o.OrderDate, o.ShippedDate)       AS DaysToShip,
        CASE WHEN o.ShippedDate > o.RequiredDate THEN 1 ELSE 0 END AS IsLate
    FROM bronze.Orders o
    JOIN silver.DimCustomer dc ON o.CustomerID = dc.CustomerID AND dc.IsCurrent = 1
    JOIN silver.DimEmployee de ON o.EmployeeID = de.EmployeeID
    JOIN silver.DimShipper  ds ON o.ShipVia    = ds.ShipperID
) AS s ON t.OrderID = s.OrderID
WHEN MATCHED
    AND t.ShippedDateKey IS NULL
    AND s.ShippedDate IS NOT NULL
    THEN UPDATE SET
        t.ShippedDateKey = CAST(FORMAT(s.ShippedDate, 'yyyyMMdd') AS INT),
        t.DaysToShip     = s.DaysToShip,
        t.IsLate         = s.IsLate
WHEN NOT MATCHED
    THEN INSERT (OrderID, CustomerSK, EmployeeSK, ShipperSK,
                 OrderDateKey, RequiredDateKey, ShippedDateKey,
                 DaysToShip, IsLate)
         VALUES (s.OrderID, s.CustomerSK, s.EmployeeSK, s.ShipperSK,
                 s.OrderDateKey, s.RequiredDateKey,
                 CASE WHEN s.ShippedDate IS NOT NULL
                      THEN CAST(FORMAT(s.ShippedDate, 'yyyyMMdd') AS INT)
                      ELSE NULL END,
                 s.DaysToShip, s.IsLate);
```

> `IS DISTINCT FROM` disponível no SQL Server 2022+. Para versões anteriores, usar lógica explícita: `(a IS NULL AND b IS NOT NULL) OR (a IS NOT NULL AND a <> b)`.

### Spark (PySpark)

```python
from delta.tables import DeltaTable

delta = DeltaTable.forName(spark, "gold.fact_order_fulfillment")
delta.alias("t") \
    .merge(source.alias("s"), "t.OrderID = s.OrderID") \
    .whenMatchedUpdate(
        condition="t.ShippedDateKey IS NULL AND s.ShippedDate IS NOT NULL",
        set={
            "ShippedDateKey": "s.ShippedDateKey",
            "DaysToShip":     "s.DaysToShip",
            "IsLate":         "s.IsLate"
        }
    ) \
    .whenNotMatchedInsertAll() \
    .execute()
```

### DuckDB

DuckDB 0.10 não tem MERGE nativo. Usar UPDATE + INSERT separados:

```python
# Atualizar pedidos que receberam ShippedDate
conn.execute(f"""
    UPDATE gold.fact_order_fulfillment t
    SET ShippedDateKey = CAST(strftime('%Y%m%d', s.ShippedDate) AS INTEGER),
        DaysToShip     = DATEDIFF('day', s.OrderDate, s.ShippedDate),
        IsLate         = CASE WHEN s.ShippedDate > s.RequiredDate THEN 1 ELSE 0 END
    FROM bronze.orders s
    WHERE t.OrderID = s.OrderID
      AND t.ShippedDateKey IS NULL
      AND s.ShippedDate IS NOT NULL
""")

# Inserir novos pedidos
conn.execute("""
    INSERT INTO gold.fact_order_fulfillment
    SELECT ...
    FROM bronze.orders o
    JOIN silver.dim_customer dc ...
    WHERE o.OrderID NOT IN (SELECT OrderID FROM gold.fact_order_fulfillment)
""")
```

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|---|---|---|
| UPDATE sempre dispara | `WHEN MATCHED` sem filtro de ShippedDate | Adicionar `AND t.ShippedDateKey IS NULL AND s.ShippedDate IS NOT NULL` |
| Linha duplicada | INSERT sem verificar existência | `WHEN NOT MATCHED` garante unicidade |
| `DaysToShip` negativo | `ShippedDate < OrderDate` (erro de dados na fonte) | Validar no lab com `WHERE DaysToShip < 0` |
| `IsLate = 0` para pedidos pendentes | `ShippedDate IS NULL` não tratado no CASE | `WHEN ShippedDate IS NULL THEN 0` antes do WHEN > RequiredDate |
| `IS DISTINCT FROM` indisponível | SQL Server < 2022 | Lógica explícita com IS NULL + `<>` |

---

## 6. Questões de Revisão

1. Qual a diferença fundamental entre Fato Transacional e Accumulating Snapshot?
2. Por que FactOrderFulfillment tem 1 linha por pedido e não 1 por item de pedido?
3. O que acontece com a linha de um pedido pendente quando `ShippedDate` é preenchida? Qual operação SQL executa essa atualização?
4. Se você rodar `sp_process_fact_fulfillment` 5 vezes seguidas sem mudar os dados, quantas linhas a mais serão inseridas?
5. Como calcular o percentual de pedidos entregues com atraso por shipper?

---

**Sessão anterior:** [T04 — Gold: Fato Transacional](T04_fato_transacional.md)
**Próxima sessão:** [T06 — Gold: Periodic Snapshot](T06_periodic_snapshot.md)
