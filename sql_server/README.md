# Executor do pipeline — `run_pipeline.py`

Atalho para quem não quer abrir os scripts um a um. Executa a construção do modelo dimensional inteiro em um comando e termina imprimindo a contagem de linhas por tabela.

Ele não substitui a leitura dos scripts — o conteúdo do projeto está no T-SQL. O caminho manual, arquivo por arquivo, está no [README principal](../README.md#executar-no-sql-server).

## Requisitos

```bash
pip install pymssql
```

Python 3.9+. Nenhuma outra dependência — o script é autocontido.

## Uso

| Sua situação | Comando |
|---|---|
| Subiu o SQL Server deste projeto via Docker | `python sql_server/run_pipeline.py` |
| SQL Server próprio | `python sql_server/run_pipeline.py --port 1433 --password SuaSenha` |
| De dentro do Jupyter Lab do projeto | `python sql_server/run_pipeline.py` |

No terceiro caso o comando funciona sem argumentos porque o `docker-compose.yml` já define `SQL_SERVER` e `SQL_PORT` apontando para o container do banco pela rede interna.

### Conexão

Precedência: **argumento > variável de ambiente > default**.

| Argumento | Variável | Default |
|---|---|---|
| `--server` | `SQL_SERVER` | `localhost` |
| `--port` | `SQL_PORT` | `1434` |
| `--user` | `SQL_USER` | `sa` |
| `--password` | `SQL_PASSWORD` | `YourPassword123` |

O default `1434` é a porta publicada pelo container deste projeto — escolhida para não conflitar com uma instalação local de SQL Server, que costuma usar `1433`. Se o seu servidor é próprio, provavelmente você quer `--port 1433`.

### Simular sem conectar

```bash
python sql_server/run_pipeline.py --dry-run
```

Lê e divide todos os scripts, imprime quantos lotes cada um tem, quais bancos são acessados e a sequência de execução — sem abrir conexão. Útil para conferir o plano, e para verificar qual destino as suas variáveis de ambiente estão produzindo antes de rodar de verdade.

## O que ele executa

**Construção** — cria estruturas e procedures, nesta ordem:

```
00_create_northwind_source.sql   01_setup.sql
02_bronze_ingest.sql             03_gold_dims.sql
04_gold_scd2.sql                 05_gold_fact_sales.sql
06_gold_fact_fulfillment.sql     07_gold_fact_stock.sql
10_bridge_table.sql              12_scd3.sql
13_factless_fact.sql
```

**Execução** — chama as procedures na ordem do pipeline:

```
bronze.sp_ingest_bronze
gold.sp_process_dims
gold.sp_process_customers_scd2
gold.sp_process_products_scd2
gold.sp_process_fact_sales
gold.sp_process_fact_fulfillment
gold.sp_process_fact_stock
gold.sp_process_bridge_employee_territory
11_junk_dimension.sql            ← arquivo inteiro, não procedure
gold.sp_load_customer_scd3_initial
gold.sp_process_customer_scd3
gold.sp_process_factless_activity
```

`11_junk_dimension.sql` aparece aqui, e não na construção, porque ele atualiza `FactSales` — precisa rodar depois que o fato existe. Executado antes, atualizaria zero linhas sem apresentar erro.

## O que ele não executa, de propósito

```
08_analytics.sql     09_validation.sql     14_role_playing.sql
```

São as demonstrações: existem para você abrir no SSMS e ler o resultado consulta a consulta. Automatizá-las produziria um despejo de saída sem valor — o ponto delas é a exploração interativa.

Os arquivos `_lab.sql` também ficam de fora: são a versão comentada passo a passo de `02` a `07`, feitos para leitura e execução por trechos.

## Comportamento

- **Para no primeiro erro**, informando arquivo e número do lote. Um pipeline que segue depois de falhar no `01_setup.sql` produz uma cascata de erros ilegível.
- **Trata `GO`** dividindo o script em lotes, como o SSMS faz — necessário porque `CREATE PROCEDURE` não pode dividir lote com outra instrução.
- **Trata `USE <banco>`** reconectando ao banco indicado; os scripts alternam entre `master`, `Northwind` e `NorthwindDW`.
- É **idempotente na prática**: rodar de novo recria as estruturas e recarrega os dados a partir da fonte.

## Notas por sistema operacional

**Windows** — se `python` não estiver no PATH, use `py -3`:

```
py -3 sql_server\run_pipeline.py
```

**Autenticação do Windows** — o executor faz login SQL (usuário e senha) via pymssql e não cobre autenticação integrada. Se é assim que você se conecta, use o caminho manual pelo SSMS descrito no README principal, que não tem essa limitação.

## Referência

`run_pipeline.sql` documenta a mesma sequência em T-SQL puro, com comentários explicando cada etapa — leitura útil para entender o pipeline antes de executá-lo, ou para rodar tudo direto do SSMS sem Python.
