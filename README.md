# Northwind DW

Pipeline de engenharia de dados completo sobre o banco **Northwind** (Microsoft), implementado em três tecnologias: **SQL Server**, **Spark + Delta Lake** e **DuckDB**.

## Diferenciais

| Padrão | Detalhe |
|--------|---------|
| **3 tipos de fato** | Transacional (FactSales) + Accumulating Snapshot (FactOrderFulfillment) + Periodic Snapshot (FactProductStock) |
| **SCD2 em 2 objetos** | DimCustomer (rastreia mudança de cidade/contato) + DimProduct (rastreia mudança de preço) |
| **Hierarquia achatada** | DimEmployee: self-join ReportsTo → ManagerName + STRING_AGG de territórios |
| **Desconto explícito** | GrossRevenue vs NetRevenue — campo Discount (0.0–1.0) do Northwind exposto no grain |
| **Lead time logístico** | FactOrderFulfillment: DaysToShip, IsLate — análise de SLA de entrega por Shipper |
| **Bridge Table** | `gold.BridgeEmployeeTerritory` resolve M:N Employee ↔ Territory (Kimball) |
| **Role-Playing Dimension** | `DimDate` reutilizada com 3 aliases (`v_OrderDate`, `v_RequiredDate`, `v_ShippedDate`) |
| **Junk Dimension** | `gold.DimOrderFlags` agrupa `DiscountBand`, `IsHighValue` e `ShipmentMode` |
| **SCD Tipo 3** | `gold.DimCustomerSCD3` rastreia `CurrentCity`/`PreviousCity` com data de mudança |
| **Factless Fact** | `gold.FactEmployeeTerritoryActivity` sem métricas — responde "quais territórios nunca tiveram cobertura?" |
| **Degenerate Dimension** | `OrderID` em `FactSales` documentado como DD para drill-through e rastreabilidade |

## Estrutura

```
pf_northwind/
├── sql_server/        # T-SQL nativo: scripts de setup, procedures e labs
├── spark_sql/         # Spark SQL + Delta Lake: notebooks 01→15
├── duckdb/            # DuckDB SQL: notebooks 01→14
└── teoria/            # T01–T14: arquivos .md de teoria por padrão
```

## Modelo Dimensional

```
                          DimDate
                            │
DimEmployee ─────────── FactSales ─────────── DimCustomer (SCD2)
DimCategory ─────────── FactSales ─────────── DimProduct  (SCD2)
DimShipper  ─────────── FactSales
                            │
                   FactOrderFulfillment        (Accumulating Snapshot — grain: Order)
                   FactProductStock            (Periodic Snapshot — grain: Product × run)
```

### Dimensões

| Dimensão | Tipo | Atributos rastreados |
|----------|------|----------------------|
| DimCustomer | SCD2 | ContactName, ContactTitle, City, Country |
| DimProduct | SCD2 | UnitPrice, Discontinued |
| DimEmployee | SCD1 | hierarquia achatada + TerritoryList |
| DimCategory | SCD1 | — |
| DimSupplier | SCD1 | — |
| DimShipper | SCD1 | — |
| DimTerritory | SCD1 | RegionName |
| DimDate | Estática | 1990–2030 |

---

## Como usar

### Só quero avaliar o projeto

Os notebooks de Spark e DuckDB já contêm os resultados das últimas execuções. Basta clonar o repositório e abrir qualquer notebook — nenhuma instalação necessária.

> **SQL Server:** os scripts T-SQL não produzem output salvo — para essa implementação é necessário um banco ativo. Veja as seções abaixo.

---

### Quero executar — Docker (recomendado)

O projeto disponibiliza um Docker com Jupyter Lab, Spark e DuckDB pré-configurados. É a forma mais rápida de executar sem configurar nada manualmente.

**Subir Jupyter Lab com Spark + DuckDB:**

```bash
docker compose -f docker/docker-compose.yml up -d
```

Acesse **http://localhost:8890** — Jupyter Lab já está no ar, sem senha.

**Subir também o SQL Server:**

```bash
docker compose -f docker/docker-compose.yml --profile sqlserver up -d
```

Aguarde ~30 s até o SQL Server inicializar, depois conecte pelo SSMS ou Azure Data Studio:

| Campo | Valor |
|-------|-------|
| Servidor | `localhost,1434` |
| Usuário | `sa` |
| Senha | `YourPassword123` |

<details>
<summary>Parar / remover containers</summary>

```bash
# Apenas Spark + DuckDB:
docker compose -f docker/docker-compose.yml down

# Spark + DuckDB + SQL Server:
docker compose -f docker/docker-compose.yml --profile sqlserver down

# Remover também os dados do SQL Server:
docker compose -f docker/docker-compose.yml --profile sqlserver down -v
```

</details>

<details>
<summary>Portas utilizadas</summary>

| Porta | Serviço |
|-------|---------|
| 8890 | Jupyter Lab |
| 4042 | Spark UI (durante jobs) |
| 1434 | SQL Server (`--profile sqlserver`) |

</details>

---

### Quero executar — SQL Server próprio

Se você já tem um SQL Server (2017+) disponível, basta executar os scripts diretamente. Use [SSMS](https://aka.ms/ssmsfullsetup) ou [Azure Data Studio](https://aka.ms/azuredatastudio) (ambos gratuitos).

Execute os scripts abaixo em ordem — cada um cria as estruturas e a procedure da sua etapa:

```
sql_server/00_create_northwind_source.sql  ← cria e popula o banco Northwind (fonte OLTP)
sql_server/01_setup.sql                    ← cria o banco NorthwindDW com schemas e tabelas
sql_server/02_bronze_ingest.sql            ← procedure bronze.sp_ingest_bronze
sql_server/03_gold_dims.sql                ← procedure gold.sp_process_dims (SCD1 + DimDate)
sql_server/04_gold_scd2.sql                ← procedures SCD2 DimCustomer + DimProduct
sql_server/05_gold_fact_sales.sql          ← procedure gold.sp_process_fact_sales
sql_server/06_gold_fact_fulfillment.sql    ← procedure gold.sp_process_fact_fulfillment
sql_server/07_gold_fact_stock.sql          ← procedure gold.sp_process_fact_stock
```

Labs interativos — versões com contexto de ensino passo a passo:

```
sql_server/02_bronze_ingest_lab.sql            ← lab bronze.sp_ingest_bronze
sql_server/03_gold_dims_lab.sql                ← lab gold.sp_process_dims
sql_server/04_gold_scd2_lab.sql                ← lab SCD2 DimCustomer + DimProduct
sql_server/05_gold_fact_sales_lab.sql          ← lab gold.sp_process_fact_sales
sql_server/06_gold_fact_fulfillment_lab.sql    ← lab gold.sp_process_fact_fulfillment
sql_server/07_gold_fact_stock_lab.sql          ← lab gold.sp_process_fact_stock
```

Com o pipeline core no ar, continue pelos padrões avançados e análises:

```
sql_server/08_analytics.sql              ← 10 queries analíticas com framing de negócio
sql_server/09_validation.sql             ← 20 verificações de integridade do modelo
sql_server/10_bridge_table.sql           ← BridgeEmployeeTerritory (M:N pattern)
sql_server/11_junk_dimension.sql         ← DimOrderFlags + atualização FactSales
sql_server/12_scd3.sql                   ← DimCustomerSCD3 + simulação sintética
sql_server/13_factless_fact.sql          ← FactEmployeeTerritoryActivity (factless)
sql_server/14_role_playing.sql           ← Views v_OrderDate/RequiredDate/ShippedDate + DD
```

**Visão macro do pipeline:** abra `sql_server/run_pipeline.sql` — ele mostra todos os `EXEC` em sequência e inclui queries demonstrativas do que foi construído.

---

### Quero executar — ambiente local sem Docker

Se preferir rodar sem Docker, configure o ambiente manualmente.

#### DuckDB

Não exige Java nem servidor. Apenas Python 3.9+:

```bash
pip install duckdb==0.10.0 pandas jupyter
jupyter notebook
```

Edite `DB_PATH` e `DATA_DIR` em `duckdb/utils.py` para apontar para o diretório correto no seu ambiente.

Pipeline core — cada notebook cria as estruturas da sua etapa:

```
duckdb/01_setup.ipynb                 ← schema e DDL
duckdb/02_bronze_ingest.ipynb         ← ingestão dos CSVs para bronze
duckdb/03_gold_dims.ipynb             ← dimensões SCD1 + DimDate
duckdb/04_gold_scd2.ipynb             ← DimCustomer e DimProduct (SCD2)
duckdb/05_gold_fact_sales.ipynb       ← FactSales (transacional)
duckdb/06_gold_fact_fulfillment.ipynb ← FactOrderFulfillment (accumulating snapshot)
duckdb/07_gold_fact_stock.ipynb       ← FactProductStock (periodic snapshot)
```

Análise e validação:

```
duckdb/08_analytics.ipynb             ← 10 queries analíticas
duckdb/09_validation.ipynb            ← 14 verificações de integridade
```

Padrões avançados:

```
duckdb/10_bridge_table.ipynb          ← BridgeEmployeeTerritory (M:N pattern)
duckdb/11_junk_dimension.ipynb        ← DimOrderFlags + UPDATE em FactSales
duckdb/12_scd3.ipynb                  ← DimCustomerSCD3 + simulação sintética
duckdb/13_factless_fact.ipynb         ← FactEmployeeTerritoryActivity (factless)
duckdb/14_role_playing.ipynb          ← Views role-playing + Degenerate Dimension
```

#### Spark + Delta Lake

Requer Java 11 ou 17.

<details>
<summary>Verificar se Java está instalado</summary>

```bash
java -version
# Esperado: openjdk version "11..." ou "17..."
```

Se não tiver: instale [OpenJDK 17](https://adoptium.net/) (Windows/Mac/Linux, gratuito).

</details>

```bash
pip install pyspark==3.5.0 delta-spark==3.0.0 jupyter
jupyter notebook
```

Edite `BASE_DIR` em `spark_sql/utils.py` para apontar para o diretório correto no seu ambiente.

Pipeline core — cada notebook cria as estruturas da sua etapa:

```
spark_sql/01_setup.ipynb                 ← schema e DDL Delta Lake
spark_sql/02_bronze_ingest.ipynb         ← ingestão dos CSVs para bronze
spark_sql/03_gold_dims.ipynb             ← dimensões SCD1 + DimDate
spark_sql/04_gold_scd2.ipynb             ← DimCustomer e DimProduct (SCD2)
spark_sql/05_gold_fact_sales.ipynb       ← FactSales (transacional)
spark_sql/06_gold_fact_fulfillment.ipynb ← FactOrderFulfillment (accumulating snapshot)
spark_sql/07_gold_fact_stock.ipynb       ← FactProductStock (periodic snapshot)
```

Análise e validação:

```
spark_sql/08_analytics.ipynb             ← 10 queries analíticas com framing de negócio
spark_sql/09_validation.ipynb            ← 14 verificações de integridade
```

Padrões avançados:

```
spark_sql/10_bridge_table.ipynb          ← BridgeEmployeeTerritory (M:N pattern)
spark_sql/11_junk_dimension.ipynb        ← DimOrderFlags + MERGE em FactSales
spark_sql/12_scd3.ipynb                  ← DimCustomerSCD3 + simulação sintética
spark_sql/13_factless_fact.ipynb         ← FactEmployeeTerritoryActivity (factless)
spark_sql/14_role_playing.ipynb          ← Views role-playing + Degenerate Dimension
spark_sql/15_delta_features.ipynb        ← Time Travel, DESCRIBE HISTORY, OPTIMIZE, Z-ORDER
```

---

## Teoria

`teoria/T01` a `T14` — documentação dos padrões aplicados neste projeto:

| Arquivo | Padrão |
|---------|--------|
| T01_bronze_ingestion.md | Full Load vs Incremental vs CDC |
| T02_scd1.md | SCD Tipo 1: sobrescrita |
| T03_scd2.md | SCD Tipo 2: histórico completo, bi-temporal queries |
| T04_fato_transacional.md | Fato Transacional (FactSales): grain, métricas |
| T05_accumulating_snapshot.md | Accumulating Snapshot (FactOrderFulfillment): milestones |
| T06_periodic_snapshot.md | Periodic Snapshot (FactProductStock): estoque por data |
| T07_bridge_table.md | Bridge Table: M:N Employee ↔ Territory (Kimball) |
| T08_role_playing_dimension.md | Role-Playing: DimDate com 3 aliases |
| T09_junk_dimension.md | Junk Dimension: consolidar flags de baixa cardinalidade |
| T10_scd3.md | SCD Tipo 3: rastrear N versões fixas de um atributo |
| T11_factless_fact.md | Factless Fact: cobertura e eventos sem métricas |
| T12_degenerate_dimension.md | Degenerate Dimension: OrderID como chave de drill-through |
| T13_spark_delta_lake.md | Spark e Delta Lake: arquitetura e recursos |
| T14_duckdb.md | DuckDB: características e uso analítico |

Cada arquivo explica o padrão, quando usar e como está implementado neste projeto.

## Fonte de dados

| Tabela | Linhas | Uso |
|--------|--------|-----|
| Customers | 91 | DimCustomer (SCD2) |
| Employees | 9 | DimEmployee |
| Products | 77 | DimProduct (SCD2) |
| Categories | 8 | DimCategory |
| Suppliers | 29 | DimSupplier |
| Shippers | 3 | DimShipper |
| Orders | 830 | FactSales + FactOrderFulfillment |
| Order Details | 2.155 | FactSales (grain = linha de pedido) |
| Territories | 53 | DimTerritory |
| Region | 4 | DimTerritory |
| EmployeeTerritories | 49 | ponte Employee ↔ Territory |
