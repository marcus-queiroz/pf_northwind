# T09 — Junk Dimension

## O que é

Uma **Junk Dimension** (dimensão lixo — o nome não é negativo, é técnico) é uma dimensão auxiliar que agrupa **atributos de baixa cardinalidade** que descrevem o contexto de uma transação mas não pertencem a nenhuma dimensão conformada.

Tipicamente são flags booleanas, indicadores categóricos e códigos de status que proliferariam como colunas soltas no fato se não fossem agrupados.

## O problema que resolve

Sem Junk Dimension, o FactSales teria colunas como:

```sql
-- Fato "wide" — anti-padrão
CREATE TABLE gold.FactSales (
    ...
    IsHighValue    BIT,          -- flag booleana
    DiscountBand   NVARCHAR(10), -- categoria derivada
    ShipmentMode   NVARCHAR(10), -- categoria derivada
    IsRushOrder    BIT,          -- outra flag
    IsPromoApplied BIT,          -- outra flag
    ...
)
```

Problemas:
- Cada nova flag exige `ALTER TABLE` no fato
- Queries `GROUP BY DiscountBand, ShipmentMode` são lentas sem índice
- Não há lugar natural para descrever a *combinação* (semântica do contexto)

## A solução: pré-gerar combinações

A Junk Dimension substitui N colunas do fato por uma única FK:

```sql
CREATE TABLE silver.DimOrderFlags (
    OrderFlagsSK INT IDENTITY(1,1) PRIMARY KEY,
    DiscountBand NVARCHAR(10) NOT NULL,  -- 'None','Low','Medium','High'
    IsHighValue  BIT          NOT NULL,  -- NetRevenue > 1000
    ShipmentMode NVARCHAR(10) NOT NULL,  -- 'Express','Standard','Economy'
    CONSTRAINT UQ_DimOrderFlags UNIQUE (DiscountBand, IsHighValue, ShipmentMode)
);
-- FK no fato: gold.FactSales.OrderFlagsSK → silver.DimOrderFlags
```

## Duas estratégias de população

### 1. Pré-geração (este portfólio)
Gerar todas as combinações possíveis com CROSS JOIN antes dos dados chegarem:

```sql
WITH combos AS (
    SELECT d.DiscountBand, v.IsHighValue, s.ShipmentMode
    FROM (VALUES ('None'), ('Low'), ('Medium'), ('High')) d(DiscountBand)
    CROSS JOIN (VALUES (0), (1)) v(IsHighValue)
    CROSS JOIN (VALUES ('Express'), ('Standard'), ('Economy')) s(ShipmentMode)
)
INSERT INTO silver.DimOrderFlags (DiscountBand, IsHighValue, ShipmentMode)
SELECT * FROM combos;
-- 4 × 2 × 3 = 24 linhas
```

Vantagem: a dimensão nunca cresce surpresa; todas as combinações já existem.

### 2. Geração dinâmica
Inserir novas combinações à medida que aparecem nos dados (como SCD1).

Vantagem: não precisar conhecer o domínio completo antecipadamente.

## Quando vale a pena

Use Junk Dimension quando:
- Você tem ≥3 flags/categorias de baixa cardinalidade no fato
- As categorias são derivadas, não conformadas (não têm dimensão própria)
- A explosão combinatória é razoável (< 100-200 combinações)

Não use quando:
- Há apenas 1-2 flags — simplesmente deixe no fato
- Os atributos têm cardinalidade alta — viram dimensão própria
- As flags têm relação causal direta com a transação (são métricas, não contexto)

## Northwind: DimOrderFlags

- `DiscountBand`: derivado do `Discount` real. Categoriza 0%, 1–5%, 6–15%, >15%
- `IsHighValue`: `NetRevenue > 1000`. Limiar arbitrário para demonstração
- `ShipmentMode`: mapeado deterministicamente por `ShipperID` (1=Express, 2=Standard, 3=Economy). **Dado sintético** — Northwind não captura canal de envio. O padrão é demonstrado com regra determinística

## Armadilhas

1. **Explosão combinatória**: 10 atributos binários = 1024 combinações. Se nem metade ocorre nos dados, a dimensão fica esparsa. Avalie o produto cartesiano antes.

2. **Atributos correlacionados**: Se `IsHighValue` e `DiscountBand` são quase sempre `High + None`, a dimensão é esparsa e o ganho analítico é baixo.

3. **Atualização de combinações**: Se o domínio dos atributos muda (novo `DiscountBand`), a dimensão precisa ser atualizada antes de novos fatos chegarem.


