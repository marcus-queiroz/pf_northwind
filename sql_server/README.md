# SQL Server — quatro portas de execução

Quatro scripts na raiz, cada um respondendo a uma pergunta diferente. As três primeiras constroem, na ordem; a quarta desfaz.

| # | Arquivo | Pergunta que responde | Natureza |
|---|---------|------------------------|----------|
| 00 | `00_create_northwind_source.sql` | Já tenho o Northwind (fonte OLTP)? | Cria se não existir — seguro rodar de novo |
| 01 | `01_setup.sql` | Já construí o banco `NorthwindDW`? | **Destrutivo** — começa com `DROP DATABASE NorthwindDW` |
| 02 | `02_build_and_load.sql` | Rodar o pipeline inteiro | Idempotente — recria e recarrega a partir da fonte |
| 03 | `03_cleanup.sql` | Quero remover tudo? | **Destrutivo** — apaga `Northwind` e `NorthwindDW` |

`01_setup.sql` apaga o banco `NorthwindDW` antes de recriar. Se você guarda algo além do que os scripts deste projeto produzem nesse banco, ele se perde. `03_cleanup.sql` vai além: também apaga o `Northwind` (a fonte OLTP), para quem quer sair do projeto sem deixar rastro no servidor. Rodar de novo depois de limpar significa recomeçar do `00`.

`02_build_and_load.sql` concatena os arquivos de `construcao/` mais a sequência de `EXEC` que roda o pipeline de ponta a ponta. Ele só constrói: define as procedures, executa cada uma uma vez, na ordem certa, e termina na contagem de linhas por tabela. Nenhuma consulta de demonstração roda no meio do caminho — isso é o que os `labs/` e as `demonstracoes/` são para.

## `construcao/`, `demonstracoes/`, `labs/`

```
construcao/       10 arquivos — criam as procedures do modelo gold
demonstracoes/    3 arquivos — exploram o que foi construído
labs/             10 arquivos — cada um executa e explora um padrão isoladamente
```

**A distinção que o repo não anuncia:** quase todo `construcao/` (`02` a `07`, `10`, `12`, `13`) é `CREATE PROCEDURE` — rodar um desses arquivos isolado apenas *define* a procedure, não mostra resultado nenhum. `11_junk_dimension.sql` é o único arquivo de construção que executa direto (popula `DimOrderFlags` e atualiza `FactSales`) — por isso ele já está embutido em `02_build_and_load.sql`, na posição correta da sequência de execução, e não como uma chamada `EXEC` a mais.

Se você quer estudar um padrão e ver acontecer sem montar o pipeline inteiro, é isso que os `labs/` resolvem: um arquivo por padrão de `construcao/` (`02` a `07`, `10`, `12`, `13`), com o `EXEC` que falta e as consultas que mostram o resultado. `11` é exceção nos dois lados: como já executa sozinho, o lab correspondente (`11_junk_dimension_lab.sql`) só explora — não tem `EXEC` porque não há o que chamar. `12_scd3_lab.sql` é o mais elaborado: Northwind é estático, então o lab simula uma mudança de cidade/país em `bronze.Customers`, roda a procedure de atualização, mostra o antes/depois, e restaura o valor original ao final.

## Por que os números não seguem a ordem de execução

A numeração é ordem de **estudo** (mesma numeração das trilhas Spark e DuckDB, para comparar o mesmo padrão nas três tecnologias), não ordem de **execução**. `11_junk_dimension.sql`, por exemplo, precisa rodar depois de `FactSales` existir — ou seja, depois dos passos que vêm numerados antes *e* depois dele. Rodado fora de ordem, ele não dá erro: atualiza zero linhas silenciosamente. É esse descompasso — número de arquivo por padrão didático vs. posição real na cadeia de dependências — que `02_build_and_load.sql` resolve, embutindo a ordem correta uma vez para sempre.

## Referência

`demonstracoes/09_validation.sql` tem a checagem 16 (Junk Dimension), que é o teste real dessa ordenação: se `11_junk_dimension.sql` tivesse ficado na posição errada, ela é quem denuncia.
