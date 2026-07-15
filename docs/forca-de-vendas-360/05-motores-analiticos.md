# 05 — Motores Analíticos

Todos os motores vivem em `app/services/engines/`, são **determinísticos e testáveis sem IA** (o Claude os consome como ferramentas, doc 06), gravam resultados versionados (doc 04) e nunca recalculam sem mudança de dados relevante.

## 5.1 Motor de projeção (`Engines::Projection`)

### Dados analisados

- Faturamento líquido, cancelamentos e devoluções;
- Pedidos confirmados, pendentes e bloqueados;
- Cotações e histórico de conversão;
- Recompras previstas;
- Dias úteis e tendência recente;
- Estoque, crédito e capacidade de faturamento;
- Sazonalidade e comportamento por carteira.

### Cenários

| Cenário | Composição |
|---|---|
| **Conservador** | Faturamento líquido + pedidos confirmados com alta probabilidade − cancelamentos e devoluções previstos |
| **Provável** | Conservador + pedidos pendentes ponderados + recompras de alta confiança + cotações avançadas |
| **Potencial** | Provável + expansão, reativação, cross-sell e oportunidades de menor confiança |

### Saída (por vendedor/dia)

| Indicador | Exemplo |
|---|---|
| Meta | R$ 180.000 |
| Realizado | R$ 112.000 |
| Projeção conservadora | R$ 153.000 |
| Projeção provável | R$ 167.500 |
| Projeção potencial | R$ 188.000 |
| Gap provável | R$ 12.500 |
| Confiança | 78% |

Mais: **atingimento esperado até hoje** (meta × proporção de dias úteis decorridos) e **ritmo diário necessário** (gap ÷ dias úteis restantes).

> A projeção não é um número isolado: `components jsonb` guarda cada parcela com origem e valor, para o agente explicar componentes, riscos e ações capazes de alterar o resultado.

Implementação: calendário de dias úteis com feriados nacionais BR (tabela local ou gem `holidays`); persistir em `projections` a cada recálculo relevante (novo sync com mudança, mudança de meta, virada de dia).

## 5.2 Motor de recompra (`Engines::Repurchase`)

### Níveis de previsão

1. Cliente; 2. Cliente + categoria; 3. Cliente + produto.

### Variáveis

- Datas e intervalos entre compras;
- Mediana, média e variação (dispersão) dos intervalos;
- Quantidade, valor e tendência;
- Sazonalidade;
- Produtos substitutos e categorias relacionadas;
- Compras extraordinárias, cancelamentos e pedidos já abertos (não prever recompra do que já está em pedido).

### Evolução do modelo (por estágio)

| Estágio | Abordagem |
|---|---|
| 1. Estatístico (MVP) | Recência, frequência, média móvel, mediana, dispersão e tendência → data esperada = última compra + mediana do intervalo; confiança inversamente proporcional à dispersão e proporcional ao nº de ciclos observados |
| 2. Preditivo | Probabilidade de compra, intervalo esperado, valor e categoria (modelo treinado no histórico) |
| 3. Aprendizado contínuo | Comparação entre data/valor previsto e data/valor real para recalibração (`repurchase_predictions.status` + `confirmed_invoice_id`) |

Saída: `repurchase_predictions` com data, valor, quantidade e confiança. Recompra **atrasada** = data esperada vencida sem compra nem pedido aberto → alimenta risco e priorização.

## 5.3 Detecção de risco, queda e cross-sell

### `Engines::Risk` — clientes em risco
Sinais: recompra atrasada além da tolerância, queda de frequência, inadimplência aberta (`overdue_titles`), redução de mix, sem contato há N dias (`activities`). Classificação da carteira: **saudável, em expansão, em atenção, em risco, inativo, novo em ativação** (usada na tela Minha Carteira).

### `Engines::ConsumptionDrop` — queda de consumo
Compara janela recente vs. média histórica do cliente (mesmo período sazonal): queda percentual por cliente, categoria e produto, com valor absoluto perdido.

### `Engines::CrossSell` — expansão de mix
Categorias/produtos presentes em clientes semelhantes (mesmo segmento/porte) e ausentes no cliente; produtos complementares aos já comprados; potencial não capturado = ticket médio da categoria nos pares × ausência.

## 5.4 Motor de priorização (`Engines::Prioritization`)

Seleciona os clientes que melhor contribuem para o objetivo atual do vendedor, considerando resultado, urgência, probabilidade, margem, risco e capacidade operacional.

### Score inicial (pesos configuráveis — persistir em tabela/config, não hardcode)

| Fator | Peso inicial |
|---|---|
| Potencial de receita | 25% |
| Probabilidade de conversão | 20% |
| Urgência | 15% |
| Contribuição para o gap | 15% |
| Risco de perda | 10% |
| Margem potencial | 10% |
| Relevância estratégica | 5% |

### Restrições (excluem ou rebaixam o cliente no plano; sempre exibidas)

- Crédito bloqueado ou inadimplência;
- Estoque insuficiente ou produto descontinuado;
- Pedido já em andamento;
- Contato recente que torne nova abordagem inadequada;
- Reclamação aberta;
- Margem abaixo da política;
- Cliente pertencente a outro vendedor.

### Estratégias adaptativas (conforme posição vs. meta)

| Situação | Prioridade predominante |
|---|---|
| Abaixo da meta | Alto valor, alta conversão, curto prazo, recompra vencida e cotação avançada |
| Próximo da meta | Menor conjunto de ações capaz de eliminar o gap com elevada probabilidade |
| Acima da meta | Margem, retenção, mix, desenvolvimento futuro e contas estratégicas |

Saída: `priorities` do dia com score, fatores decompostos, motivos, potencial, ação sugerida e restrições — limitado à **capacidade diária** do vendedor (nº configurável de ações/dia).

## 5.5 Simulador para alcançar a meta (`Engines::GoalSimulator`)

Combina oportunidades suficientes para eliminar o gap, respeitando dias úteis, capacidade diária, prazo de faturamento, probabilidade, margem e risco.

Exemplo de saída:

| Origem | Clientes | Potencial |
|---|---|---|
| Recompras atrasadas | 8 | R$ 11.000 |
| Cotações abertas | 4 | R$ 8.500 |
| Cross-sell | 5 | R$ 4.000 |
| Reativação | 2 | R$ 3.500 |
| **Total** | **19** | **R$ 27.000** |

> **Princípio de otimização**: não selecionar apenas as maiores oportunidades, e sim a combinação com melhor relação entre impacto, probabilidade, prazo e esforço comercial. MVP: heurística gulosa por valor esperado (valor × probabilidade ÷ esforço) com restrição de capacidade — um knapsack simples; refinar depois.

## Aprendizado (transversal)

Comparar **previsão → recomendação → ação → resultado**:
- Recompra prevista × compra real (data/valor) → recalibrar confiança;
- Recomendação aceita/descartada + feedback do vendedor → ajustar pesos;
- Projeção do início do mês × fechamento → acurácia por vendedor (dashboard do gestor).
