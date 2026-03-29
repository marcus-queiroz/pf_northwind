# DuckDB — Visão Geral

Implementação do pipeline Northwind DW usando **DuckDB** — banco de dados analítico embarcado, sem servidor, sem instalação além do pacote Python.

Os dados são lidos diretamente dos CSVs na pasta `data/` e o banco persiste em um arquivo `.duckdb` local.

## Pré-requisito

Para executar os notebooks, instale as dependências ou use o Docker do projeto. Veja o `README.md` na raiz do projeto.

> **Só quer ler?** Os notebooks já contêm os resultados das últimas execuções. Abra qualquer um diretamente — nenhuma instalação necessária.

## Ordem de execução

### Pipeline core (01–07)

| Notebook | O que faz |
|----------|-----------|
| `01_setup.ipynb` | Cria schemas e tabelas (bronze, silver, gold) |
| `02_bronze_ingest.ipynb` | Ingere os CSVs para a camada bronze |
| `03_gold_dims.ipynb` | Dimensões SCD1 + DimDate (1990–2030) |
| `04_gold_scd2.ipynb` | DimCustomer e DimProduct com rastreamento histórico (SCD2) |
| `05_gold_fact_sales.ipynb` | FactSales — fato transacional (grain: linha de pedido) |
| `06_gold_fact_fulfillment.ipynb` | FactOrderFulfillment — accumulating snapshot (grain: pedido) |
| `07_gold_fact_stock.ipynb` | FactProductStock — periodic snapshot (grain: produto × data) |

### Análise (08)

| Notebook | O que faz |
|----------|-----------|
| `08_analytics.ipynb` | 10 queries analíticas com framing de negócio |

### Análise e validação (08–09)

| Notebook | O que faz |
|----------|-----------|
| `08_analytics.ipynb` | 10 queries analíticas com framing de negócio |
| `09_validation.ipynb` | 14 verificações de integridade do modelo |

### Padrões avançados (10–14)

| Notebook | O que faz |
|----------|-----------|
| `10_bridge_table.ipynb` | BridgeEmployeeTerritory — resolve M:N Employee ↔ Territory |
| `11_junk_dimension.ipynb` | DimOrderFlags — consolida flags de baixa cardinalidade |
| `12_scd3.ipynb` | DimCustomerSCD3 — rastreia versão atual e anterior de atributos |
| `13_factless_fact.ipynb` | FactEmployeeTerritoryActivity — fato sem métricas |
| `14_role_playing.ipynb` | Views role-playing + Degenerate Dimension |

## Caminhos dos arquivos

Os notebooks apontam para `/workspace/pf_northwind/` — caminho padrão do Docker do projeto.

Para execução local fora do Docker, edite `DB_PATH` e `DATA_DIR` em `utils.py`.
