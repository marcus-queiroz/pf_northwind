# T13 — Apache Spark + Delta Lake

**Frente:** Contextualização da camada tecnológica Spark
**Implementação:** `spark_sql/` (notebooks 01–15)

---

## Objetivos

- Entender o que é Apache Spark e por que ele é usado para pipelines de dados em escala
- Compreender o que é Delta Lake e o problema que ele resolve em relação ao Parquet puro
- Mapear os padrões de API usados no projeto (DataFrame, DeltaTable, saveAsTable)
- Saber por que certas construções existem (hash como SK, overwrite vs append, etc.)

---

## 1. Apache Spark

### O que é

Apache Spark é um framework de **processamento distribuído em memória**. Ele divide dados em partições distribuídas entre nós de um cluster e processa em paralelo, tornando viável trabalhar com volumes que não cabem em um único servidor.

Para portfólios e laptops, Spark roda em **modo local** — um único processo que simula o comportamento distribuído sem cluster real. É suficiente para aprender os padrões.

```
[SparkSession]
     │
     ├── DataFrame API  (transformações em Python/Scala/Java)
     ├── Spark SQL       (consultas via spark.sql("SELECT ..."))
     └── Structured Streaming  (fora do escopo deste projeto)
```

### SparkSession

Ponto de entrada único para tudo no Spark moderno (Spark 2.0+):

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("NorthwindDW") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()
```

As duas configs de `delta` habilitam o Delta Lake como formato padrão para `saveAsTable`.

### DataFrame vs SQL

Spark permite escrever a mesma transformação de duas formas equivalentes:

```python
# DataFrame API
df_result = df_orders \
    .join(df_customers, "CustomerID") \
    .groupBy("Country") \
    .agg(F.sum("GrossRevenue").alias("TotalRevenue"))

# Spark SQL (equivalente)
spark.sql("""
    SELECT c.Country, SUM(f.GrossRevenue) AS TotalRevenue
    FROM gold.fact_sales f
    JOIN gold.dim_customer c ON f.CustomerSK = c.CustomerSK
    GROUP BY c.Country
""")
```

Neste projeto usamos primariamente **DataFrame API** para carga/transformação e **Spark SQL** para analytics.

---

## 2. Delta Lake

### O problema com Parquet puro

Parquet é um formato de arquivo colunar excelente para leitura analítica — mas é apenas um arquivo. Sem uma camada acima dele:

| Problema | Parquet puro | Com Delta Lake |
|----------|-------------|----------------|
| Escrita concorrente | Corrompe arquivos | ACID garante consistência |
| Rollback de uma carga errada | Impossível sem backup | Time Travel (`VERSION AS OF`) |
| Schema mudou de versão para versão | Sem controle | Schema enforcement e evolution |
| UPDATE/DELETE em dados | Reescreve tudo manualmente | `DeltaTable.update()`, `.delete()` |
| Auditoria de mudanças | Nenhuma | `DESCRIBE HISTORY` |

### Como funciona

Delta Lake é uma **camada sobre Parquet** que adiciona um transaction log:

```
warehouse/gold.db/fact_sales/
├── _delta_log/              ← transaction log (JSON por commit)
│   ├── 00000000000000000000.json
│   ├── 00000000000000000001.json
│   └── ...
├── part-00000-...snappy.parquet
├── part-00001-...snappy.parquet
└── ...
```

Cada escrita ou MERGE gera uma nova entrada no `_delta_log`. O Spark lê o log para saber quais arquivos fazem parte da versão atual da tabela.

### ACID no contexto do Delta

- **Atomicidade:** uma escrita ou falha completamente ou não acontece (o log só é atualizado se tudo deu certo)
- **Consistência:** schema enforcement impede inserção de colunas com tipos errados
- **Isolamento:** leitores e escritores não se bloqueiam mutuamente (MVCC)
- **Durabilidade:** uma vez que o log registrou o commit, os dados persistem

---

## 3. Padrões de API Usados no Projeto

### Leitura

```python
# CSV → DataFrame (bronze ingest)
df = spark.read.csv("data/customers.csv", header=True, inferSchema=True)

# employees.csv tem quebras de linha em campos de endereço
df_emp = spark.read.csv("data/employees.csv", header=True, inferSchema=True,
                         multiLine=True)  # obrigatório

# Ler tabela Delta existente
df = spark.read.format("delta").table("bronze.orders")
# ou simplesmente após registrar no catálogo:
df = spark.table("bronze.orders")
```

### Escrita

```python
# Overwrite completo (equivalente a TRUNCATE + INSERT)
df.write.format("delta").mode("overwrite").saveAsTable("bronze.customers")

# Append (Periodic Snapshot — nunca sobrescreve)
df_snapshot.write.format("delta").mode("append").saveAsTable("gold.fact_product_stock")
```

`saveAsTable` registra a tabela no **Hive metastore local** (dentro do warehouse), tornando-a consultável por nome em qualquer notebook da mesma sessão.

### MERGE (DeltaTable)

MERGE é o padrão central para SCD e Accumulating Snapshot:

```python
from delta.tables import DeltaTable

delta_tgt = DeltaTable.forName(spark, "gold.dim_customer")

delta_tgt.alias("tgt") \
    .merge(
        source=df_new.alias("src"),
        condition="tgt.CustomerID = src.CustomerID AND tgt.IsCurrent = 1"
    ) \
    .whenMatchedUpdate(
        condition="src.City <> tgt.City OR src.Country <> tgt.Country",
        set={"IsCurrent": "0", "ValidTo": "date_sub(current_date(), 1)"}
    ) \
    .whenNotMatchedInsert(values={...}) \
    .execute()
```

### UPDATE direto

Para SCD2, o padrão usado no projeto é: `update()` para expirar a versão antiga + `append` para inserir a nova versão (mais explícito que um MERGE bidirecional):

```python
# Expirar versões antigas
delta_tgt.update(
    condition=f"CustomerID IN ({changed_ids}) AND IsCurrent = 1",
    set={"ValidTo": "date_sub(current_date(), 1)", "IsCurrent": "0"}
)

# Inserir novas versões
new_versions_df.write.format("delta").mode("append").saveAsTable("gold.dim_customer")
```

### Surrogate Keys com hash

Em Spark, SKs determinísticos usam hash da natural key:

```python
import pyspark.sql.functions as F

# SCD1: hash só da NK
df = df.withColumn("CustomerSK", F.abs(F.hash("CustomerID")).cast("int"))

# SCD2: hash da NK + ValidFrom (garante SK único por versão)
df = df.withColumn("CustomerSK", F.abs(F.hash("CustomerID", "ValidFrom")).cast("int"))
```

Por que `F.abs`? `F.hash()` pode retornar negativos; SKs negativos funcionam tecnicamente, mas são estranhos em relatórios.

---

## 4. Delta Lake no Contexto do Projeto

### Estrutura de warehouse

```
spark_sql/warehouse/
├── bronze.db/            ← tabelas bronze (cópia CSV)
│   ├── customers/
│   ├── orders/
│   └── ...
├── silver.db/            ← não usado neste projeto (vai direto para gold)
└── gold.db/              ← modelo dimensional
    ├── dim_customer/
    ├── dim_product/
    ├── fact_sales/
    └── ...
```

Cada subdiretório é uma tabela Delta com seus próprios arquivos Parquet e `_delta_log`.

### Time Travel (notebook 15)

```python
# Ver histórico de commits
spark.sql("DESCRIBE HISTORY gold.dim_customer").show(truncate=False)

# Ler versão anterior
df_old = spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .table("gold.dim_customer")
```

### OPTIMIZE e Z-ORDER

```python
spark.sql("OPTIMIZE gold.fact_sales ZORDER BY (CustomerSK, OrderDate)")
```

- `OPTIMIZE`: compacta arquivos pequenos em arquivos maiores (melhora leitura)
- `ZORDER BY`: co-localiza dados por coluna(s) nos arquivos (melhora queries filtradas por essas colunas)

---

## 5. Armadilhas Comuns

| Armadilha | Causa | Como evitar |
|-----------|-------|-------------|
| `EmployeeID` inferido como STRING | `employees.csv` tem `\n` em endereços; sem `multiLine=True` o Spark lê linhas parciais | Sempre usar `.option("multiLine", True)` para este arquivo |
| `overwrite` apaga schema e dados | `mode("overwrite")` com `.option("overwriteSchema", True)` reescreve DDL | Usar apenas quando schema realmente mudou |
| `saveAsTable` vs `save(path)` | `saveAsTable` registra no catálogo (nome permanece entre sessões); `save(path)` cria arquivo mas não registra nome | Usar `saveAsTable` para todas as tabelas do projeto |
| SK SCD2 idêntico entre versões | Hash só da NK → dois registros do mesmo cliente com mesmo SK | Incluir `ValidFrom` no hash para SCD2 |
| MERGE sem `alias` causa erro | `delta_tgt.merge(source, condition)` precisa de `.alias()` em ambos os lados | Sempre fazer `.alias("tgt")` e `.alias("src")` |

---

## 6. Questões de Revisão

1. Qual o problema que o Delta Lake resolve em relação ao Parquet puro? Cite dois cenários concretos.
2. Por que `saveAsTable("gold.dim_customer")` é preferível a `save("warehouse/gold.db/dim_customer")`?
3. No projeto, SCD1 usa `hash(NK)` e SCD2 usa `hash(NK, ValidFrom)`. Por quê a diferença?
4. O que acontece se você rodar `mode("overwrite")` em uma tabela Delta que já tem dados? E se você rodar `mode("append")`?
5. Você leu um CSV de employees com `inferSchema=True` e sem `multiLine=True`. Como saberia que algo deu errado antes de tentar o MERGE?

---

**Sessão anterior:** [T12 — Degenerate Dimension](T12_degenerate_dimension.md)
**Próxima sessão:** [T14 — DuckDB](T14_duckdb.md)
