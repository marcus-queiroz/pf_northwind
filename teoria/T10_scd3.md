# T10 — SCD Tipo 3 (Histórico Limitado)

## O trio SCD

| Tipo | Histórico | Mecanismo | Quando usar |
|------|-----------|-----------|-------------|
| SCD1 | Nenhum | Sobrescreve | Atributo sem valor histórico |
| SCD2 | Completo | Nova linha por versão | Quando qualquer mudança importa |
| SCD3 | Limitado (1 versão anterior) | Colunas `Previous` | Apenas a última transição importa |

## O que é SCD3

O **SCD Tipo 3** adiciona colunas `PreviousX`, `CurrentX` e `XChangedOn` ao mesmo registro da dimensão. Não cria nova linha — atualiza o registro existente rotacionando os valores:

```
Antes da mudança:  CurrentCity = 'Berlin',  PreviousCity = NULL
Após a mudança:    CurrentCity = 'Lyon',    PreviousCity = 'Berlin', CityChangedOn = '2026-03-28'
```

## Implementação

### DDL

```sql
CREATE TABLE silver.DimCustomerSCD3 (
    CustomerID       NCHAR(5)     NOT NULL PRIMARY KEY,
    CompanyName      NVARCHAR(40) NOT NULL,
    ContactName      NVARCHAR(30) NULL,
    CurrentCity      NVARCHAR(15) NULL,
    PreviousCity     NVARCHAR(15) NULL,   -- NULL se nunca mudou
    CityChangedOn    DATE         NULL,   -- NULL se nunca mudou
    CurrentCountry   NVARCHAR(15) NULL,
    PreviousCountry  NVARCHAR(15) NULL,
    CountryChangedOn DATE         NULL,
    LoadTimestamp    DATETIME     DEFAULT GETDATE()
);
```

### Procedure de atualização (SQL Server)

```sql
UPDATE scd3
SET
    PreviousCity  = scd3.CurrentCity,       -- rotacionar
    CityChangedOn = CAST(GETDATE() AS DATE), -- registrar quando
    CurrentCity   = b.City                  -- novo valor
FROM silver.DimCustomerSCD3 scd3
JOIN bronze.Customers b ON b.CustomerID = scd3.CustomerID
WHERE ISNULL(b.City, '') <> ISNULL(scd3.CurrentCity, '');
```

## Vantagens

- **Simples**: nenhuma multiplicação de linhas; queries sem filtro `IsCurrent`
- **Joins naturais**: `FROM DimCustomerSCD3 dc JOIN FactSales fs ...` sem cláusula de vigência
- **Relatórios de transição**: "Mostre clientes que mudaram de cidade" é uma query trivial

```sql
SELECT CustomerID, CurrentCity AS Atual, PreviousCity AS Anterior, CityChangedOn AS MudouEm
FROM silver.DimCustomerSCD3
WHERE PreviousCity IS NOT NULL;
```

## Desvantagens

- **Apenas 1 versão anterior**: se o cliente mudar de cidade 3 vezes, a primeira cidade é perdida
- **Sem rastreamento de múltiplas mudanças**: SCD2 registra cada transição; SCD3 registra apenas a mais recente
- **Não reconstrói o passado completamente**: impossível saber "onde o cliente estava em 1997" se houve múltiplas mudanças

## Quando escolher SCD3 sobre SCD2

Use SCD3 quando:
- O requisito de negócio é explicitamente "mostre o atual e o anterior" — sem interesse em histórico completo
- O atributo muda raramente e a última mudança é suficiente para análise
- Você quer simplicidade sem custo de múltiplas linhas por cliente

Use SCD2 quando:
- Precisar reconstruir o estado histórico exato em qualquer ponto no tempo
- Fatos históricos precisam ser vinculados à versão correta da dimensão
- O atributo pode mudar frequentemente

## Comparação direta com SCD2

```sql
-- SCD3: 1 linha por cliente, 2 valores de cidade visíveis
SELECT CustomerID, CurrentCity, PreviousCity FROM silver.DimCustomerSCD3;

-- SCD2: N linhas por cliente, cada uma com vigência explícita
SELECT CustomerID, City, ValidFrom, ValidTo, IsCurrent FROM silver.DimCustomer;
```

## No portfólio Northwind

`DimCustomerSCD3` é uma **tabela separada** — não substitui nem altera `DimCustomer` (SCD2). Isso permite comparação direta entre os padrões:

- `silver.DimCustomer`: SCD2 completo com histórico de `ContactName` e `City`
- `silver.DimCustomerSCD3`: SCD3 com apenas `CurrentCity`/`PreviousCity`

## Perguntas de revisão

1. Se um cliente muda de cidade três vezes, o que cada padrão (SCD1, SCD2, SCD3) registra?
2. Por que SCD3 não exige filtro `IsCurrent` nas queries?
3. Em que cenário SCD3 é preferível a SCD2, mesmo perdendo histórico completo?
4. Como a procedure de atualização SCD3 previne sobrescrever `PreviousCity` com `NULL`?
