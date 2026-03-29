# T11 — Factless Fact Table

## O que é

Uma **Factless Fact Table** (tabela fato sem métricas) é uma tabela fato que contém apenas chaves de dimensão — sem nenhuma medida numérica. Registra que **um evento ocorreu** ou que **uma combinação de dimensões é válida**, sem quantificar nada.

A pergunta que ela responde: **"O que não aconteceu?"**

## Dois tipos de Factless Fact

### 1. Tipo Evento
Registra a ocorrência de um evento no mundo real:
- "O aluno assistiu a aula X no dia Y"
- "O empregado processou pedidos no território Z no dia D"
- "O cliente visitou a loja em tal data"

### 2. Tipo Cobertura
Registra quais combinações *deveriam* acontecer (para servir de denominador em análises):
- "Esses são os alunos matriculados nesse curso" → permite calcular taxa de presença
- "Esses são os territórios atribuídos ao empregado" → permite calcular cobertura

## Exemplo Northwind: FactEmployeeTerritoryActivity

```sql
CREATE TABLE gold.FactEmployeeTerritoryActivity (
    ActivityDateKey INT NOT NULL,    -- quando
    EmployeeSK      INT NOT NULL,    -- quem
    TerritorySK     INT NOT NULL,    -- onde
    CONSTRAINT PK_FactEmployeeTerritoryActivity
        PRIMARY KEY (ActivityDateKey, EmployeeSK, TerritorySK)
    -- Sem métricas — só chaves
);
```

**Grain:** um registro por (dia, empregado, território) — registra que o empregado processou pelo menos um pedido naquele dia e está associado a aquele território via Bridge.

## Queries habilitadas por Factless Fact

### "O que NÃO aconteceu?" (a mais poderosa)
```sql
-- Territórios que o empregado cobre mas onde nunca processou pedidos
SELECT dt.TerritoryDescription, de.FullName AS Empregado
FROM silver.BridgeEmployeeTerritory b
JOIN silver.DimTerritory dt ON dt.TerritorySK = b.TerritorySK
JOIN silver.DimEmployee  de ON de.EmployeeSK  = b.EmployeeSK
WHERE NOT EXISTS (
    SELECT 1 FROM gold.FactEmployeeTerritoryActivity fa
    WHERE fa.EmployeeSK = b.EmployeeSK AND fa.TerritorySK = b.TerritorySK
);
```

### Contagem de eventos (como se fossem métricas)
```sql
-- Dias de atividade por empregado e território
SELECT de.FullName, dt.TerritoryDescription, COUNT(*) AS DiasAtivos
FROM gold.FactEmployeeTerritoryActivity fa
JOIN silver.DimEmployee  de ON de.EmployeeSK  = fa.EmployeeSK
JOIN silver.DimTerritory dt ON dt.TerritorySK = fa.TerritorySK
GROUP BY de.FullName, dt.TerritoryDescription;
```

O `COUNT(*)` aqui *não* é uma métrica do fato — é contagem de eventos.

## Diferença da Factless Fact para outros padrões

| Padrão | Tem métricas? | Responde "o que não aconteceu?" |
|--------|--------------|--------------------------------|
| Fato Transacional | Sim | Não naturalmente |
| Accumulating Snapshot | Sim (milestones) | Parcialmente |
| Periodic Snapshot | Sim | Não |
| **Factless Fact** | **Não** | **Sim (com NOT EXISTS)** |

## Armadilhas

1. **Confundir com log/auditoria**: Log registra qualquer evento técnico. Factless Fact tem grain analítico deliberado — não é "toda chamada HTTP", é "o evento de negócio relevante".

2. **Grain muito fino**: Registrar cada item de pedido × território cria uma tabela enorme com pouco ganho analítico. O grain deve ser o nível mínimo útil para análise.

3. **Sem índices adequados**: Factless facts são frequentemente usadas em `NOT EXISTS` — índice composto em `(EmployeeSK, TerritorySK)` é essencial para performance.

4. **Perguntar "mas onde estão as métricas?"**: A ausência de métricas é a característica, não um bug. Resistir à tentação de adicionar `OrderCount` ou similares — se você precisa de métricas, é um fato transacional.

## Perguntas de revisão

1. Qual é a diferença entre Factless Fact tipo Evento e tipo Cobertura?
2. Por que a query "o que NÃO aconteceu?" é difícil com fatos transacionais normais?
3. Como `COUNT(*)` em uma Factless Fact difere de uma métrica no fato?
4. Por que `NOT EXISTS` sobre uma Factless Fact é mais eficiente que uma solução alternativa sem ela?
