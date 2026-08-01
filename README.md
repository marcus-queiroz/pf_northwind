# Northwind DW

Os principais padrões de modelagem dimensional implementados três vezes — em **SQL Server**, **Spark + Delta Lake** e **DuckDB** — sobre a mesma base Northwind, com a mesma numeração de arquivos nas três trilhas. Serve tanto como pipeline completo quanto como referência de consulta: para ver como um Accumulating Snapshot fica em cada tecnologia, basta abrir o arquivo `06` das três pastas.

Os notebooks de Spark e DuckDB estão versionados **com os outputs das últimas execuções** — dá para avaliar o projeto inteiro lendo no GitHub, sem clonar e sem instalar nada.

---

## O que está entregue

**Trilha SQL Server** (`sql_server/`) — T-SQL nativo, do banco fonte ao modelo dimensional:

```
00_create_northwind_source.sql  cria e popula o banco Northwind (fonte OLTP)
01_setup.sql                    cria o banco NorthwindDW: schemas, tabelas e views
02_bronze_ingest.sql            procedure de ingestão para a camada bronze
03_gold_dims.sql                dimensões SCD1 + DimDate
04_gold_scd2.sql                DimCustomer e DimProduct com histórico (SCD2)
05_gold_fact_sales.sql          FactSales — fato transacional
06_gold_fact_fulfillment.sql    FactOrderFulfillment — accumulating snapshot
07_gold_fact_stock.sql          FactProductStock — periodic snapshot
10_bridge_table.sql             BridgeEmployeeTerritory — resolve M:N
11_junk_dimension.sql           DimOrderFlags + atualização de FactSales
12_scd3.sql                     DimCustomerSCD3 — histórico de N versões fixas
13_factless_fact.sql            FactEmployeeTerritoryActivity — fato sem métrica
```

**Demonstrações** — não constroem nada, servem para explorar o que foi construído:

```
08_analytics.sql                10 queries analíticas com framing de negócio
09_validation.sql               20 verificações de integridade do modelo
14_role_playing.sql             views role-playing + degenerate dimension
```

**Labs** — versões didáticas de `02` a `07`, com o passo a passo comentado e as consultas intermediárias que mostram o antes e o depois de cada transformação:

```
02_bronze_ingest_lab.sql   03_gold_dims_lab.sql   04_gold_scd2_lab.sql
05_gold_fact_sales_lab.sql 06_gold_fact_fulfillment_lab.sql 07_gold_fact_stock_lab.sql
```

**Trilhas Spark e DuckDB** (`spark_sql/`, `duckdb/`) — os mesmos passos em notebooks, com a mesma numeração e os outputs salvos.

---

## Executar no SQL Server

Pré-requisito: um SQL Server 2017 ou superior e um cliente para rodar os scripts — [SSMS](https://aka.ms/ssmsfullsetup) ou [Azure Data Studio](https://aka.ms/azuredatastudio), ambos gratuitos. Se você não tem um SQL Server à mão, o projeto fornece um pronto via Docker (ver [Ambiente](#ambiente), no fim).

**1. Criar as estruturas e as procedures**

Abra e execute, nesta ordem: `00_create_northwind_source.sql`, `01_setup.sql`, depois `02` a `07`, e por fim `10`, `12` e `13`. Cada arquivo cria as estruturas e a procedure da sua etapa.

**2. Executar o pipeline**

Abra e execute `run_pipeline.sql` — ele chama todas as procedures na ordem correta e termina com a contagem de linhas por tabela e duas consultas de resultado.

**3. Popular a Junk Dimension**

Execute `11_junk_dimension.sql`. Ele não usa procedure e precisa rodar **depois** do passo 2: atualiza `FactSales`, que só existe a partir dali. Rodado antes, atualiza zero linhas sem apresentar erro.

**4. Explorar**

Abra `08_analytics.sql`, `09_validation.sql` e `14_role_playing.sql` para ver o modelo respondendo perguntas de negócio e passando nas verificações de integridade.

### Atalho: executor Python

Se preferir não rodar os arquivos um a um, `run_pipeline.py` faz os passos 1 a 3 em um comando:

| Sua situação | Comando |
|---|---|
| Subiu o SQL Server deste projeto via Docker | `python sql_server/run_pipeline.py` |
| SQL Server próprio | `python sql_server/run_pipeline.py --port 1433 --password SuaSenha` |
| De dentro do Jupyter Lab do projeto | `python sql_server/run_pipeline.py` |

Requer `pip install pymssql`. Flags, variáveis de ambiente, modo de simulação e o que o executor deliberadamente **não** roda estão em **[`sql_server/README.md`](sql_server/README.md)**.

---

## O valor: um referencial portátil

Cada padrão aparece nas três tecnologias sob o mesmo número, ao lado do texto de teoria que o explica. Para estudar um padrão, leia a teoria e compare as três implementações lado a lado:

| Padrão | Teoria | SQL Server | Spark | DuckDB |
|---|---|---|---|---|
| Ingestão bronze | T01 | `02_bronze_ingest.sql` | `02_bronze_ingest.ipynb` | `02_bronze_ingest.ipynb` |
| SCD Tipo 1 | T02 | `03_gold_dims.sql` | `03_gold_dims.ipynb` | `03_gold_dims.ipynb` |
| SCD Tipo 2 | T03 | `04_gold_scd2.sql` | `04_gold_scd2.ipynb` | `04_gold_scd2.ipynb` |
| Fato transacional | T04 | `05_gold_fact_sales.sql` | `05_gold_fact_sales.ipynb` | `05_gold_fact_sales.ipynb` |
| Accumulating snapshot | T05 | `06_gold_fact_fulfillment.sql` | `06_gold_fact_fulfillment.ipynb` | `06_gold_fact_fulfillment.ipynb` |
| Periodic snapshot | T06 | `07_gold_fact_stock.sql` | `07_gold_fact_stock.ipynb` | `07_gold_fact_stock.ipynb` |
| Bridge table (M:N) | T07 | `10_bridge_table.sql` | `10_bridge_table.ipynb` | `10_bridge_table.ipynb` |
| Junk dimension | T09 | `11_junk_dimension.sql` | `11_junk_dimension.ipynb` | `11_junk_dimension.ipynb` |
| SCD Tipo 3 | T10 | `12_scd3.sql` | `12_scd3.ipynb` | `12_scd3.ipynb` |
| Factless fact | T11 | `13_factless_fact.sql` | `13_factless_fact.ipynb` | `13_factless_fact.ipynb` |
| Role-playing + degenerate | T08, T12 | `14_role_playing.sql` | `14_role_playing.ipynb` | `14_role_playing.ipynb` |
| Recursos do Delta Lake | T13 | — | `15_delta_features.ipynb` | — |

O paralelo é o ponto: o mesmo SCD2 escrito com `MERGE` em T-SQL, com a API Delta em Spark e em SQL analítico puro no DuckDB mostra o que é essência do padrão e o que é sotaque da ferramenta.

### Diferenciais

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

### Modelo dimensional

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

### Teoria

`teoria/T01` a `T14` — cada arquivo explica o padrão, quando usar e como está implementado aqui:

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

### Fonte de dados

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

---

## Estrutura

```
pf_northwind/
├── sql_server/        # T-SQL: scripts de construção, demonstrações, labs e o executor
├── spark_sql/         # Spark SQL + Delta Lake: notebooks 01→15
├── duckdb/            # DuckDB SQL: notebooks 01→14
├── teoria/            # T01–T14: um arquivo de teoria por padrão
└── docker/            # ambiente pronto: Jupyter Lab, Spark, DuckDB e SQL Server
```

---

## Ambiente

Você não precisa de nada disto para **ler** o projeto — os notebooks já vêm com os outputs. Esta seção é para quem quer executar.

O projeto entrega dois ambientes prontos em Docker, independentes entre si:

- **Notebooks** — Jupyter Lab com Spark, Delta Lake e DuckDB já configurados.
- **Banco** — SQL Server 2022, para a trilha T-SQL.

Escolha o que precisa:

```bash
# Só os notebooks (Spark + DuckDB):
docker compose -f docker/docker-compose.yml up -d

# Só o SQL Server:
docker compose -f docker/docker-compose.yml --profile sqlserver up -d sqlserver

# Os dois:
docker compose -f docker/docker-compose.yml --profile sqlserver up -d
```

**Notebooks:** acesse **http://localhost:8890** — Jupyter Lab no ar, sem senha.

**Banco:** aguarde cerca de 30 segundos até o SQL Server inicializar e conecte pelo SSMS ou Azure Data Studio:

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

### Sem Docker

**DuckDB** — não exige Java nem servidor, apenas Python 3.9+:

```bash
pip install duckdb==0.10.0 pandas jupyter
jupyter notebook
```

Pipeline: `01_setup` → `02_bronze_ingest` → `03_gold_dims` → `04_gold_scd2` → `05_gold_fact_sales` → `06_gold_fact_fulfillment` → `07_gold_fact_stock`. Depois `08_analytics` e `09_validation`; padrões avançados em `10` a `14`.

**Spark + Delta Lake** — requer Java 11 ou 17:

```bash
pip install pyspark==3.5.0 delta-spark==3.0.0 jupyter
jupyter notebook
```

<details>
<summary>Verificar se Java está instalado</summary>

```bash
java -version
# Esperado: openjdk version "11..." ou "17..."
```

Se não tiver: instale [OpenJDK 17](https://adoptium.net/) (Windows/Mac/Linux, gratuito).

</details>

Mesma sequência do DuckDB, mais `15_delta_features` (time travel, `DESCRIBE HISTORY`, `OPTIMIZE`, Z-ORDER).
