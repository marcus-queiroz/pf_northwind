# T08 — Role-Playing Dimension

## O que é

Uma **Role-Playing Dimension** é uma dimensão física única que aparece múltiplas vezes no mesmo fato com **papéis semânticos diferentes**. A dimensão DimDate é o exemplo clássico: um único pedido tem data de criação, data de vencimento e data de envio — três papéis do mesmo calendário.

## Quando usar

Sempre que o mesmo tipo de atributo descritivo aparecer mais de uma vez em um fato com significados distintos:

- **DimDate**: OrderDate, RequiredDate, ShippedDate, DeliveryDate
- **DimLocation**: Origem, Destino, Local de faturamento
- **DimCustomer**: Comprador, Destinatário, Pagador
- **DimProduct**: Produto vendido, Produto devolvido, Produto substituído

## Implementação

### Solução correta: Views com nomes descritivos

```sql
-- Uma única tabela física
CREATE TABLE gold.DimDate (DateKey INT PRIMARY KEY, FullDate DATE, Year SMALLINT, ...);

-- Três views — um "papel" para cada uso no fato
CREATE VIEW gold.v_OrderDate    AS SELECT * FROM gold.DimDate;
CREATE VIEW gold.v_RequiredDate AS SELECT * FROM gold.DimDate;
CREATE VIEW gold.v_ShippedDate  AS SELECT * FROM gold.DimDate;
```

### Uso no FactOrderFulfillment

```sql
SELECT
    od.Year, od.Quarter,
    COUNT(DISTINCT f.OrderID) AS TotalPedidos,
    AVG(f.DaysToShip)          AS MediaDias
FROM gold.FactOrderFulfillment f
JOIN gold.v_OrderDate    od ON od.DateKey = f.OrderDateKey      -- papel: criação
LEFT JOIN gold.v_RequiredDate rd ON rd.DateKey = f.RequiredDateKey  -- papel: prazo
LEFT JOIN gold.v_ShippedDate  sd ON sd.DateKey = f.ShippedDateKey   -- papel: envio
GROUP BY od.Year, od.Quarter
ORDER BY od.Year, od.Quarter;
```

Cada view tem nome semântico — `v_OrderDate` deixa claro que o join é com a *data do pedido*. Sem as views, o desenvolvedor encontraria três joins em `gold.DimDate` com aliases diferentes, o que é válido mas menos legível e não documenta o padrão.

## Solução errada: Tabelas duplicadas

```sql
-- ERRADO — duplica storage e sincronização
CREATE TABLE gold.DimOrderDate    AS SELECT * FROM gold.DimDate;
CREATE TABLE gold.DimRequiredDate AS SELECT * FROM gold.DimDate;
CREATE TABLE gold.DimShippedDate  AS SELECT * FROM gold.DimDate;
```

Criar cópias da dimensão:
- Triplicam o uso de storage
- Exigem sincronização a cada carga (três processos idênticos)
- Não há benefício analítico — os dados são idênticos

## Armadilhas

1. **LEFT JOIN vs INNER JOIN**: Datas como ShippedDate podem ser NULL (pedido ainda não enviado). Use LEFT JOIN nas views de datas opcionais.

2. **Aliases no SQL**: Mesmo sem views, você pode usar aliases (`DimDate AS OrderDate`). As views são melhores para documentação e reusabilidade em ferramentas de BI que inspecionam o catálogo.

3. **Filtro por papel**: `WHERE od.Year = 1997` filtra pedidos *criados* em 1997. `WHERE sd.Year = 1997` filtra pedidos *enviados* em 1997. Confundir os papéis gera resultados errados silenciosos.

## No portfólio Northwind

`FactOrderFulfillment` tem três FKs para `DimDate`:
- `OrderDateKey` → `v_OrderDate` (quando o pedido foi criado)
- `RequiredDateKey` → `v_RequiredDate` (prazo prometido ao cliente)
- `ShippedDateKey` → `v_ShippedDate` (quando realmente saiu — pode ser NULL)

## Perguntas de revisão

1. Por que views são a solução correta para role-playing, não cópias da tabela?
2. Por que ShippedDate exige LEFT JOIN mas OrderDate não?
3. Cite dois exemplos de role-playing dimension além de DimDate.
4. Como o conceito de role-playing se relaciona com o princípio DRY (Don't Repeat Yourself)?
