# T12 — Degenerate Dimension

## O que é

Uma **Degenerate Dimension** (DD) é uma chave de negócio mantida diretamente no fato que:
- **Não tem tabela dimensão própria** (não há DimOrder, DimInvoice, etc.)
- **Não tem atributos descritivos** — é apenas uma chave de rastreabilidade
- **Permite drill-through**: reagrupar linhas do fato pelo identificador da transação original

O exemplo clássico: o número do pedido (`OrderID`) em uma tabela de linha de pedido.

## Por que não criar DimOrder?

Criar `DimOrder` seria legítimo somente se houvesse atributos descritivos *do pedido* que não fossem métricas e que você quisesse filtrar/agrupar. Por exemplo:

- Tipo do pedido (urgente, padrão, internacional) → vale dimensão
- Canal de venda (web, telefone, loja) → vale dimensão
- Número do pedido, ID do pedido → sem atributos adicionais → degenerate dimension

No Northwind, `FactOrderFulfillment` já captura os milestones do pedido (datas, shipper, frete). Criar um `DimOrder` paralelo seria redundância sem ganho analítico.

## Implementação

Sem implementação especial — a chave já está no fato:

```sql
CREATE TABLE gold.FactSales (
    SalesSK      INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ...
    OrderID      INT NOT NULL,  -- Degenerate Dimension: NK do pedido original
    ProductID    INT NOT NULL,  -- Degenerate Dimension: NK do produto (redundante com ProductSK, mantido para deduplicação)
    ...
);
```

A diferença de uma DD para um simples campo de auditoria é **intencionalidade**: a DD é parte do modelo dimensional, nomeada e documentada como tal.

## Usos da Degenerate Dimension

### Drill-through: reconstruir o pedido original
```sql
DECLARE @OrderID INT = 10248;

SELECT fs.OrderID,  -- Degenerate Dimension como chave de drill
       dc.CompanyName, dp.ProductName,
       fs.Quantity, fs.NetRevenue
FROM gold.FactSales fs
JOIN silver.DimCustomer dc ON dc.CustomerSK = fs.CustomerSK AND dc.IsCurrent = 1
JOIN silver.DimProduct  dp ON dp.ProductSK  = fs.ProductSK  AND dp.IsCurrent = 1
WHERE fs.OrderID = @OrderID;
```

### Agrupamento por transação
```sql
-- Total por pedido — OrderID como agrupador, não como FK
SELECT fs.OrderID, MIN(d.FullDate) AS DataPedido, SUM(fs.NetRevenue) AS Total
FROM gold.FactSales fs
JOIN silver.DimDate d ON d.DateKey = fs.OrderDateKey
GROUP BY fs.OrderID
ORDER BY DataPedido;
```

## Nomenclatura e vocabulário

No vocabulário Kimball, documentar explicitamente que `OrderID` é uma DD comunica ao próximo desenvolvedor:
- "Não existe DimOrder intencionalmente"
- "Este campo serve para drill-through, não para análise dimensional"
- "É uma chave de negócio, não surrogate key"

Sem essa documentação, um desenvolvedor pode questionar "por que não tem DimOrder?" e ser tentado a criar uma desnecessariamente.

## Casos clássicos

| Campo | Contexto | Por que é DD |
|-------|----------|--------------|
| Número do pedido | FactSales | O pedido em si está em FactOrderFulfillment |
| Número da NF | FactSales/FactShipment | Rastreabilidade fiscal, sem atributos próprios |
| Número do cheque | FactPayment | Identificador de rastreio, sem atributos |
| Número do lote | FactProduction | Rastreabilidade de produção |

## Armadilha: confundir DD com FK de dimensão "esquecida"

```sql
-- FactSales.OrderID é DD (sem DimOrder)
-- FactSales.CustomerSK é FK (com DimCustomer)
-- FactSales.EmployeeSK é FK (com DimEmployee)
```

Se existe uma tabela de dimensão para o campo, é FK, não DD. Se não existe (e não deveria existir), é DD.

## Perguntas de revisão

1. Qual é a diferença entre uma Degenerate Dimension e uma FK para uma dimensão?
2. Por que o `OrderID` em `FactSales` é considerado DD enquanto o pedido inteiro está em `FactOrderFulfillment`?
3. O que é "drill-through" e como a DD o habilita?
4. Por que documentar explicitamente uma DD é importante para manutenção do DW?

---

**Sessão anterior:** [T11 — Factless Fact](T11_factless_fact.md)
**Próxima sessão:** [T13 — Apache Spark + Delta Lake](T13_spark_delta_lake.md)
