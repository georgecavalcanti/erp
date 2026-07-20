# 06 — Agente Comercial Claude

## Papel do agente

Na primeira versão, **um único agente orquestrador**. Ele recebe o contexto institucional da Jatto, consulta ferramentas controladas e produz respostas estruturadas. A simplicidade reduz custo, latência e risco de inconsistência.

### Responsabilidades

- Identificar quais consultas e análises são necessárias para cada pergunta.
- Executar as ferramentas de projeção, recompra, risco, cross-sell e priorização.
- Combinar resultados num plano compatível com a capacidade e o tempo do vendedor.
- Explicar o diagnóstico, as evidências, o impacto potencial e o nível de confiança.
- Preparar mensagens, roteiros de ligação e perguntas para visitas.
- Registrar limitações, dados ausentes e restrições comerciais.

## Arquitetura de implementação

```
app/services/agent/
  orchestrator.rb      # loop de tool use com a Claude API
  context_builder.rb   # contexto institucional + posição do vendedor (cacheável)
  tool_registry.rb     # registro das ferramentas com JSON Schema
  tools/               # uma classe por ferramenta (Consulta / Análise / Ação preparada)
```

- Claude API com **tool use** e **saídas estruturadas** (structured outputs) para o formato padrão de recomendação.
- **Prompt caching** para instruções institucionais, definições de ferramentas e políticas estáveis.
- Toda execução grava um `agent_run` (modelo, ferramentas chamadas com parâmetros, tokens, custo, latência, status).
- Ferramentas recebem **sempre** o usuário autenticado e escopam por carteira (doc 07). O modelo não escolhe o escopo — a aplicação injeta.

> **Regra central**: o Claude não recebe credenciais do Sankhya e não acessa diretamente o ERP. Ferramentas internas autenticadas fazem isso por ele.

## Ferramentas autorizadas

### Grupo Consulta (leem a base comercial; algumas consultam o Sankhya em tempo real)

| Ferramenta | Retorna |
|---|---|
| `consultar_meta` | Meta do vendedor no período (valor, margem mínima, complementares) |
| `consultar_resultado_vendedor` | Realizado, atingimento, ritmo, gap, projeções vigentes |
| `consultar_cliente_360` | Consolidado do cliente: receita, margem, ticket, frequência, mix, situação, crédito |
| `consultar_vendas_cliente` | Histórico de vendas/itens do cliente (período parametrizável) |
| `consultar_pedidos_abertos` | Pedidos pendentes/bloqueados do cliente ou da carteira |
| `consultar_estoque` | Disponibilidade de produto(s) — **tempo real** com fallback ao espelho |
| `consultar_precos` | Preço vigente e tabela aplicável — **tempo real** com fallback |
| `consultar_credito` | Limite, saldo em aberto, bloqueio, inadimplência — **tempo real** com fallback |
| `consultar_interacoes` | Atividades/contatos registrados com o cliente |

### Grupo Análise (invocam os motores do doc 05)

`calcular_projecao` · `prever_recompra` · `detectar_clientes_em_risco` · `detectar_queda_de_consumo` · `identificar_cross_sell` · `calcular_potencial_cliente` · `priorizar_carteira` · `simular_plano_para_meta`

Regra: essas ferramentas **retornam resultados persistidos/versionados** dos motores (recalculando apenas se os dados mudaram) — o agente interpreta e combina, não refaz a matemática.

### Grupo Ação preparada (escrevem apenas na base local; nunca no ERP)

| Ferramenta | Efeito |
|---|---|
| `registrar_contato` / `registrar_visita` / `registrar_observacao` | Cria `activity` |
| `criar_tarefa` | Cria `activity` kind=task com prazo |
| `registrar_resultado` | Vincula resultado a uma recomendação (feedback + receita influenciada) |
| `preparar_mensagem` | Gera rascunho de mensagem (WhatsApp/e-mail) — **não envia**; usuário revisa e envia |
| `preparar_cotacao` | Gera rascunho de cotação — **não fatura, não grava no ERP** |

Cada ferramenta declara JSON Schema de entrada/saída no `tool_registry`. Os contratos detalhados são escritos na Sprint 8 (artefato "Contratos JSON das ferramentas").

## Formato padrão de recomendação (structured output)

| Campo | Conteúdo |
|---|---|
| Diagnóstico | Situação encontrada e causa principal |
| Recomendação | Ação comercial sugerida |
| Evidências | Dados utilizados e período analisado |
| Impacto potencial | Receita, margem ou retenção esperada |
| Confiança | Nível calculado e fatores que o limitam |
| Próxima ação | Atividade objetiva, canal e responsável |
| Prazo | Data ou janela recomendada |
| Restrições | Crédito, estoque, preço, reclamações ou dados ausentes |

Persistido em `recommendations` com `tools_used` e `agent_run_id`.

## Limites obrigatórios

- **Não inventar valores** ou completar dados ausentes — indicar ausência e pedir atualização da fonte.
- Não informar estoque, preço ou crédito sem consulta válida.
- Não alterar preços, conceder descontos ou modificar crédito.
- Não faturar pedidos nem modificar metas.
- Não transferir carteiras.
- Não enviar mensagens externas sem aprovação do usuário.

### Regras de segurança da IA

| Permitido | Exige aprovação ou é proibido |
|---|---|
| Consultar dados autorizados; analisar; simular; preparar mensagens e cotações | Enviar comunicação externa; alterar preço; conceder desconto; modificar crédito; faturar; alterar meta; transferir carteira |
| Indicar ausência de dados e pedir atualização da fonte | Inventar valores, estoque, prazo ou condições comerciais |

Aplicação prática: o conjunto de ferramentas registradas simplesmente **não contém** operações proibidas; as "ações preparadas" criam rascunhos com status pendente de aprovação humana.

## Casos de uso do copiloto

| Comando do vendedor | Resposta esperada |
|---|---|
| "Monte meu plano para hoje." | Lista priorizada, potencial, abordagem e sequência de execução |
| "Quais clientes podem cobrir meu gap?" | Combinação de contas e oportunidades suficiente para a meta |
| "Prepare minha conversa com a Empresa Alfa." | Resumo, histórico, riscos, perguntas e produtos sugeridos |
| "Onde estou perdendo margem?" | Clientes, produtos, descontos e ações corretivas |
| "Explique minha projeção." | Componentes, riscos, confiança e alternativas |

## Estratégia de custos de IA

1. Não enviar todo o histórico ao Claude; consultar somente os dados necessários (via ferramentas).
2. Resumir resultados em estruturas compactas e reutilizáveis.
3. Utilizar **prompt caching** para instruções, ferramentas e políticas estáveis.
4. Executar previsões pesadas **em lote fora do horário comercial** (motores rodam sem IA; o agente só interpreta).
5. Atualizar prioridades somente quando houver mudança relevante nos dados.
6. Utilizar modelos adequados à complexidade (ex.: `CLAUDE_MODEL_LIGHT` para resumos simples, `CLAUDE_MODEL_DEFAULT` para plano/copiloto).
7. Armazenar resultados e **não recalcular perguntas idênticas** sem alteração dos dados (cache por digest de pergunta+estado).
8. **Tetos diários de custo em US$** (controle primário): global `AGENT_DAILY_COST_BUDGET_USD`
   (default US$ 20 — "não passar disso contando tudo") e por vendedor `AGENT_DAILY_COST_PER_SELLER_USD`
   (default US$ 1, para um vendedor não consumir o orçamento inteiro). Atingido o teto, o agente
   **degrada** (última resposta válida + aviso) em vez de estourar o orçamento, e registra alerta
   (grupo IA, doc 09) — com aviso ao cruzar 80%. Backstop absoluto em tokens: `AGENT_DAILY_TOKEN_BUDGET`.

### Seleção de modelos (decisão, 19/07/2026)

**Premissa que barateia tudo:** a análise cara (recompra, risco, queda, priorização, gap) já é
**determinística e local** (Sprints 4–7) — roda sem IA, custo zero. O agente **não analisa dado cru**;
ele só **orquestra ferramentas + sintetiza a recomendação (structured output) + escreve o resumo**.
É tarefa de orquestração/redação sobre dado pré-digerido → **um modelo pequeno basta**.

- **Runtime em produção do agente: `claude-haiku-4-5`** ($1/$5 por 1M in/out) para plano do dia,
  resumo e copiloto de rotina. **Escala para `claude-sonnet-5`** ($3/$15; intro $2/$10 até 31/08/2026)
  só nos casos complexos (`CLAUDE_MODEL_LIGHT` = Haiku, `CLAUDE_MODEL_DEFAULT` = Sonnet). Opus fica
  para desenvolvimento, não para o runtime.
- **Alavancas que importam mais que o modelo:** (a) **prompt caching** do contexto institucional/
  ferramentas (leitura de cache ~0,1× do input — o maior bloco do prompt é reusado em todo
  vendedor/dia); (b) **Batch API** (−50%) no lote noturno de planos; (c) tiering por complexidade.
- **Ordem de grandeza** (Haiku + cache): ~$0,01–0,015 por vendedor/dia → dezenas de dólares/mês para a
  equipe toda. O **fornecedor não é onde está o custo** — as alavancas acima pesam muito mais que trocar
  Claude por um modelo "mini" de outro fornecedor, que ainda custaria a re-plumbagem da camada de agente
  e o re-teste do invariante de segurança (tool allowlist + escopo por carteira, doc 07). Preços conferir
  em `platform.claude.com/docs/en/pricing` antes de fechar orçamento.

## Resiliência

Se o Claude estiver indisponível: cockpit, indicadores, prioridades e planos já persistidos continuam acessíveis (motores são determinísticos e locais). O copiloto exibe estado degradado com a última resposta válida.

## Referências técnicas

- Sankhya Developer — API de Integrações / Autenticação OAuth / Consulta de registros
- Anthropic — Tool use · Structured outputs · Prompt caching
