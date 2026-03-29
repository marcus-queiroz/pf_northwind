# T07 — Bridge Table

## O que é

A Bridge Table (ou tabela-ponte) é o padrão Kimball para resolver relações **M:N** entre uma dimensão e um fato — ou entre duas dimensões. Quando um empregado cobre múltiplos territórios e um território é coberto por múltiplos empregados, a relação não cabe em nenhuma das tabelas sem duplicação.

## Quando usar

Use Bridge Table quando:
- Uma FK no fato apontaria para múltiplos registros da dimensão (M:N real)
- Você precisa analisar métricas *por* cada lado da relação M:N
- O volume de combinações é razoável (não explode cardinalidade)

Exemplos comuns:
- Empregado ↔ Território
- Produto ↔ Categoria de promoção
- Pedido ↔ Agente de suporte

## Solução errada: STRING_AGG

```sql
-- DimEmployee.TerritoryList = "Atlanta, Savannah, Tampa"
-- Impossível filtrar por "Atlanta" de forma eficiente
-- Impossível somar receita por território sem parsing
```

Quando o campo é uma string concatenada, você perde a granularidade analítica. Não há como fazer `JOIN` direto com DimTerritory — é necessário `LIKE '%Atlanta%'`, que é lento e impreciso.

## Solução correta: Bridge Table

```
FactSales ──→ DimEmployee ──→ BridgeEmployeeTerritory ──→ DimTerritory
                                    (bridge)
```

O grain da bridge é `(EmployeeSK, TerritorySK)` — uma linha por combinação válida.

```sql
CREATE TABLE silver.BridgeEmployeeTerritory (
    EmployeeSK  INT NOT NULL,
    TerritorySK INT NOT NULL,
    CONSTRAINT PK_BridgeEmployeeTerritory PRIMARY KEY (EmployeeSK, TerritorySK)
);
```

## WeightFactor (extensão avançada)

Quando você soma métricas do fato passando pela bridge, cada linha de venda é contada *N* vezes (uma por território do empregado). Para evitar **double-counting**, Kimball recomenda adicionar `WeightFactor = 1/N`:

```sql
ALTER TABLE silver.BridgeEmployeeTerritory
ADD WeightFactor DECIMAL(5,4) NULL;
-- Exemplo: empregado com 4 territórios → WeightFactor = 0.25 em cada
```

Neste portfólio, a bridge não tem WeightFactor porque a análise é *contagem de eventos* (qual território gerou X pedidos), não *distribuição de receita* por território — portanto não há double-counting.

## Implementação

### SQL Server
```sql
INSERT INTO silver.BridgeEmployeeTerritory (EmployeeSK, TerritorySK)
SELECT DISTINCT de.EmployeeSK, dt.TerritorySK
FROM bronze.EmployeeTerritories et
JOIN silver.DimEmployee  de ON de.EmployeeID  = et.EmployeeID
JOIN silver.DimTerritory dt ON dt.TerritoryID = et.TerritoryID;
```

### Query analítica (o valor da bridge)
```sql
SELECT dt.TerritoryDescription, SUM(fs.NetRevenue) AS Receita
FROM gold.FactSales fs
JOIN silver.DimEmployee             de ON de.EmployeeSK  = fs.EmployeeSK
JOIN silver.BridgeEmployeeTerritory b  ON b.EmployeeSK   = de.EmployeeSK
JOIN silver.DimTerritory            dt ON dt.TerritorySK = b.TerritorySK
GROUP BY dt.TerritoryDescription
ORDER BY Receita DESC;
```

## Armadilhas

1. **Double-counting**: Sem WeightFactor, somar receita pela bridge multiplica cada venda pelo número de territórios do empregado. Use COUNT(DISTINCT OrderID) em vez de SUM quando a intenção é contar pedidos.

2. **Carga da bridge**: A bridge deve ser recarregada sempre que a relação M:N mudar (empregado ganha/perde território). Use TRUNCATE + INSERT (simples) ou MERGE (incremental).

3. **Confundir bridge com tabela de fato**: A bridge não tem métricas. É puramente estrutural.

## Perguntas de revisão

1. Por que STRING_AGG em DimEmployee é inadequado para análise territorial?
2. Quando é necessário usar WeightFactor na bridge?
3. Qual é o grain correto de uma Bridge Table Employee-Territory?
4. Como a Bridge Table habilita a query "quais territórios nunca geraram pedidos"?
