# SQL Server — quatro portas de execução

Quatro scripts na raiz, cada um respondendo a uma pergunta diferente. As três primeiras constroem, na ordem; a quarta desfaz.

| # | Arquivo | Pergunta que responde | Natureza |
|---|---------|------------------------|----------|
| 00 | `00_create_northwind_source.sql` | Já tenho o Northwind (fonte OLTP)? | Cria se não existir — seguro rodar de novo |
| 01 | `01_setup.sql` | Já construí o banco `NorthwindDW`? | **Destrutivo** — começa com `DROP DATABASE NorthwindDW` |
| 02 | `02_build_and_load.sql` | Rodar o pipeline inteiro | Idempotente — recria e recarrega a partir da fonte |
| 03 | `03_cleanup.sql` | Quero remover tudo? | **Destrutivo** — apaga `Northwind` e `NorthwindDW` |

`01_setup.sql` apaga o banco `NorthwindDW` antes de recriar. Se você guarda algo além do que os scripts deste projeto produzem nesse banco, ele se perde. `03_cleanup.sql` vai além: também apaga o `Northwind` (a fonte OLTP), para quem quer sair do projeto sem deixar rastro no servidor. Rodar de novo depois de limpar significa recomeçar do `00`.

## Onde editar vs. o que é gerado

`02_build_and_load.sql` é **gerado** — não edite à mão. Ele concatena os arquivos de `construcao/` (a fonte real) mais a sequência de `EXEC` que roda o pipeline de ponta a ponta.

Para mudar alguma procedure, edite o arquivo correspondente em `construcao/` e regenere (a partir da raiz do projeto):

```bash
.tools/gen_build_and_load.sh
```

## `construcao/`, `demonstracoes/`, `labs/`

```
construcao/       10 arquivos — criam as procedures do modelo gold
demonstracoes/    3 arquivos — exploram o que foi construído
labs/             6 arquivos — versão comentada passo a passo de 02 a 07
```

**A distinção que o repo não anuncia:** a maioria de `construcao/` (`02` a `07`, `10`, `12`, `13`) é `CREATE PROCEDURE` — rodar um desses arquivos isolado apenas *define* a procedure, não mostra resultado nenhum. `11_junk_dimension.sql` é o único arquivo de construção que executa direto (popula `DimOrderFlags` e atualiza `FactSales`) — por isso ele já está embutido em `02_build_and_load.sql`, na posição correta da sequência de execução, e não como uma chamada `EXEC` a mais.

Se você quer estudar um padrão e ver acontecer sem montar o pipeline inteiro, é isso que os `labs/` resolvem: mesma lógica de `02` a `07`, mas comentada por trecho e com as consultas intermediárias que mostram o antes e o depois.

## Por que os números não seguem a ordem de execução

A numeração é ordem de **estudo** (mesma numeração das trilhas Spark e DuckDB, para comparar o mesmo padrão nas três tecnologias), não ordem de **execução**. `11_junk_dimension.sql`, por exemplo, precisa rodar depois de `FactSales` existir — ou seja, depois dos passos que vêm numerados antes *e* depois dele. Rodado fora de ordem, ele não dá erro: atualiza zero linhas silenciosamente. É esse descompasso — número de arquivo por padrão didático vs. posição real na cadeia de dependências — que `02_build_and_load.sql` resolve, embutindo a ordem correta uma vez para sempre.

## Referência

`demonstracoes/09_validation.sql` tem a checagem 16 (Junk Dimension), que é o teste real dessa ordenação: se `11_junk_dimension.sql` tivesse ficado na posição errada, ela é quem denuncia.
