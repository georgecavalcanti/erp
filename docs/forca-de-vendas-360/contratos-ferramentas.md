# Contratos JSON das Ferramentas do Agente Claude

> Artefato da Sprint 8 (doc 10). Fonte da verdade executável: `app/services/agent/tools/*` +
> `Agent::ToolRegistry` (allowlist). Este documento descreve o contrato de cada ferramenta:
> entrada (JSON Schema exposto ao modelo), saída (shape devolvido como `tool_result`),
> escopo aplicado e erros possíveis.

## Regras transversais (valem para TODAS as ferramentas)

1. **Escopo injetado, nunca escolhido pelo modelo.** O `ToolRegistry` é instanciado com o
   usuário autenticado e o vendedor de contexto (resolvidos e validados pelo controller via
   `AccessPolicy`). Nenhum schema expõe `salesperson_id`. Referências a cliente (`partner_id`)
   passam por `authorized_partner!` — cliente fora da carteira → erro `Denied` (fail-closed).
2. **Allowlist.** Ferramenta que não está em `ToolRegistry::TOOL_CLASSES` **não existe**:
   o pedido vira `tool_result` de erro, nunca execução (doc 09).
3. **Ausência explícita.** Sem dado ou sem fonte integrada, a resposta declara a ausência em
   `aviso` — o agente comunica a limitação; **nunca inventa** valor, estoque, preço ou prazo.
4. **Erros nunca derrubam o loop.** `registry.call` devolve `{ ok: false, error: "..." }`;
   o orquestrador converte em `tool_result` com `is_error: true` e o modelo se corrige.
5. **Sankhya é só-leitura e invisível ao agente.** Só `consultar_estoque` toca o ERP em tempo
   real, e por dentro do `Sankhya::LiveQueries` (credenciais nunca chegam ao modelo). O grupo
   Ação escreve **somente** na base local (`activities`, `recommendations`, `influenced_revenues`).
6. Todos os schemas usam `additionalProperties: false`. Valores monetários saem como `number`
   (Float, 2 casas). Datas em ISO 8601.

---

## Grupo Consulta (9)

### `consultar_meta`
Meta do vendedor no período.

- **Entrada**: `{ mes?: string /^\d{4}-\d{2}$/ }` — default: mês corrente.
- **Saída**: `{ vendedor, periodo, metas: [{ tipo: revenue|margin|mix|activation, valor,
  margem_minima_percent?, complementares? }], aviso? }`. Sem meta → `metas: []` + aviso.
- **Escopo**: vendedor do contexto (`salesperson!`).
- **Erros**: mês inválido; sem vendedor no contexto.

### `consultar_resultado_vendedor`
Posição do mês: realizado, atingimento, ritmo, gap e cenários (Engines::Projection ao vivo — mesmo motor do Cockpit).

- **Entrada**: `{}`
- **Saída**: `{ vendedor, mes, meta?, realizado, margem_realizada, atingimento_percent?,
  esperado_ate_hoje, ritmo_diario_necessario, dias_uteis, cenarios: { conservative|likely|potential:
  { valor, gap?, confianca } }, aviso? }`
- **Escopo**: vendedor do contexto.

### `consultar_cliente_360`
Consolidado do cliente (Customer360Report: espelho local).

- **Entrada**: `{ partner_id: integer }` (obrigatório)
- **Saída**: `{ cadastro: {...}, resumo: { revenue_total, revenue_12m, margin_total,
  margin_percent, invoice_count, avg_ticket, last_purchase_on, days_since_last, ... },
  financeiro: { blocked, block_reason, overdue_open, overdue_protested, overdue_total },
  mix_categorias: [...] }`
- **Escopo**: `authorized_partner!`.

### `consultar_vendas_cliente`
Histórico de vendas do cliente (evolução mensal líquida + top produtos).

- **Entrada**: `{ partner_id: integer, meses?: integer 1..24 }` — default 6.
- **Saída**: `{ cliente, janela_meses, evolucao_mensal: [...], top_produtos: [...] }`
- **Escopo**: `authorized_partner!`.

### `consultar_pedidos_abertos`
Pedidos pendentes (Order.portfolio) do cliente ou da carteira.

- **Entrada**: `{ partner_id?: integer }`
- **Saída**: `{ quantidade, valor_total, pedidos: [{ numero, cliente, data, valor, situacao?,
  tipo_entrega? }] }` (máx. 30 listados)
- **Escopo**: com `partner_id` → `authorized_partner!`; sem → carteira do vendedor do contexto.

### `consultar_estoque`
Disponibilidade de produto(s). **Tempo real** (Sankhya::LiveQueries) quando a busca resolve em
1 produto; snapshot do espelho quando há vários. Catálogo é global (não recortado por carteira).

- **Entrada**: `{ produto: string (código CODPROD ou termo, minLength 2) }`
- **Saída**: `{ produtos: [{ codigo, descricao, unidade?, disponivel: number|null,
  origem: "live"|"snapshot"|"unavailable", dado_de: iso8601|null }], aviso? }` (máx. 5)
- **Regra doc 06**: a origem e o carimbo SEMPRE acompanham o dado; sem fonte → `unavailable`.

### `consultar_precos`
Preço vigente. **Fonte ainda não integrada** (TGFTAB/TGFEXC sem sync) — a ferramenta existe
para o agente responder a ausência com honestidade.

- **Entrada**: `{ produto: string }`
- **Saída**: `{ disponivel: false, aviso: "...consultar no Sankhya... NÃO estime preços." }`
- **Evolução**: quando o sync de preços existir, o `execute` passa a consultá-lo (contrato de
  saída ganhará `precos: [...]` com origem/carimbo, mantendo o fallback honesto).

### `consultar_credito`
Situação de crédito (Fase 0: crédito = bloqueio + inadimplência; LIMCRED não integrado).

- **Entrada**: `{ partner_id: integer }`
- **Saída**: `{ cliente, bloqueado, motivo_bloqueio?, titulos_vencidos: { quantidade,
  valor_aberto, valor_protestado, maior_atraso_dias? }, origem: "espelho", dado_de, aviso }`
- **Escopo**: `authorized_partner!`.

### `consultar_interacoes`
Atividades registradas com o cliente.

- **Entrada**: `{ partner_id: integer, limite?: integer 1..30 }` — default 10.
- **Saída**: `{ cliente, interacoes: [{ tipo, canal?, quando, notas? }], aviso? }`
- **Escopo**: `authorized_partner!`.

---

## Grupo Análise (8)

Regra do grupo (doc 06): devolvem o resultado **persistido/versionado** dos motores
determinísticos (Sprints 4–7); sem persistência → calculam ao vivo **sem persistir** e
declaram a origem em `origem`. O agente interpreta e combina — não refaz a matemática.

### `calcular_projecao`
- **Entrada**: `{}` · **Escopo**: vendedor do contexto.
- **Saída**: `{ vendedor, origem, referencia?, meta?, realizado, cenarios: [{ cenario, valor,
  margem?, gap?, confianca, parcelas: [...] }] }` — `parcelas` são as componentes rastreáveis
  (explicabilidade, doc 04).
- **Fonte**: leva mais recente de `projections` do mês; fallback `Engines::Projection#call`.

### `prever_recompra`
- **Entrada**: `{ partner_id: integer }` · **Escopo**: `authorized_partner!`.
- **Saída**: `{ cliente, origem, previsoes: [{ nivel: customer|category|product, alvo?,
  data_esperada, valor_esperado, confianca, atrasada_dias }], aviso? }`
- **Fonte**: `repurchase_predictions` abertas; fallback `Engines::Repurchase#call`.
  Histórico insuficiente → `previsoes: []` + aviso (não inventa).

### `detectar_clientes_em_risco`
- **Entrada**: `{}` · **Escopo**: carteira do vendedor do contexto (Wallet.active).
- **Saída**: `{ carteira, em_alerta, clientes: [{ partner_id, cliente, status: em_risco|inativo|
  em_atencao, rotulo, sinais: [...], dias_sem_comprar?, dias_sem_contato?, inadimplencia }],
  aviso? }` (top 20 por criticidade)
- **Fonte**: `Engines::Risk.classify_many` (determinístico, em lote).

### `detectar_queda_de_consumo`
- **Entrada**: `{}` · **Escopo**: carteira do vendedor do contexto.
- **Saída**: `{ carteira, em_queda, clientes: [{ partner_id, cliente, queda_percent,
  ritmo_recente, linha_de_base, perda_estimada }] }` (top 15 por perda)
- **Fonte**: `Engines::ConsumptionDrop.for_partners`.

### `identificar_cross_sell`
- **Entrada**: `{ partner_id: integer }` · **Escopo**: `authorized_partner!`.
- **Saída**: `{ cliente, oportunidades: [{ categoria, pares_comprando, potencial }], aviso? }`
- **Fonte**: `Engines::CrossSell#call` (pares por porte/UF, potencial = mediana).

### `calcular_potencial_cliente`
- **Entrada**: `{ partner_id: integer }` · **Escopo**: `authorized_partner!`.
- **Saída**: `{ cliente, potencial_total, decomposicao: { recompras_abertas, cross_sell,
  recuperacao_queda }, tendencia_consumo }`
- **Fonte**: COMBINA sinais persistidos/motores (recompra + cross-sell + queda).

### `priorizar_carteira`
- **Entrada**: `{}` · **Escopo**: vendedor do contexto.
- **Saída**: `{ vendedor, origem, prioridades: [{ posicao, partner_id, cliente, score,
  motivos: [...], potencial, urgencia, acao_sugerida?, restricoes: [...] }] }` (top 15)
- **Fonte**: `priorities` do dia; fallback `Engines::Prioritization#call`.

### `simular_plano_para_meta`
- **Entrada**: `{}` · **Escopo**: vendedor do contexto.
- **Saída**: `{ vendedor, gap?, capacidade_diaria, valor_esperado_total, cobre_o_gap,
  oportunidades: [{ partner_id, cliente, potencial, probabilidade, valor_esperado, origem }],
  por_origem: {...}, aviso? }`
- **Fonte**: `Engines::GoalSimulator#call` (guloso por valor esperado; restrições duras excluem).

---

## Grupo Ação preparada (7)

Regra do grupo (doc 06): escrevem **somente na base local**, com autoria do usuário
autenticado. Nada é enviado ao cliente; nada toca o ERP. Rascunhos saem do sistema apenas
por ação humana explícita.

### `registrar_contato` · `registrar_visita` · `registrar_observacao`
Criam `Activity` (kinds `contact` / `visit` / `note`).

- **Entrada**: `{ partner_id: integer, notas: string (minLength 3),
  canal?: ligacao|whatsapp|visita|email|interno, quando?: string ISO 8601 }`
- **Saída**: `{ registrado: true, atividade_id, cliente, tipo, quando }`
- **Escopo**: `authorized_partner!` — negado = nenhuma escrita.

### `criar_tarefa`
Cria `Activity` kind `task` com prazo em `outcome.prazo`.

- **Entrada**: `{ partner_id: integer, notas: string, prazo: string YYYY-MM-DD (hoje+) }`
- **Saída**: `{ registrado: true, atividade_id, cliente, tarefa, prazo }`
- **Erros**: prazo no passado ou formato inválido.

### `registrar_resultado`
Resultado comercial de uma recomendação: cria `InfluencedRevenue` + `Activity(result)` e
conclui a recomendação (mesma regra do `RecommendationsController#result`).

- **Entrada**: `{ recommendation_id: integer, valor: number > 0, nota_uid?: integer (NUNOTA),
  notas?: string }`
- **Saída**: `{ registrado: true, recomendacao_id, cliente?, valor_influenciado, nota? }`
- **Escopo**: recomendação de vendedor autorizado (`authorized_salesperson_ids`); a nota
  (se informada) tem de ser DO cliente da recomendação.
- **Erros**: resultado já registrado; nota de outro cliente; recomendação fora do escopo.

### `preparar_mensagem`
Salva o rascunho de mensagem redigido pelo agente como `Activity` (kind `note`,
`outcome.tipo = "rascunho_mensagem"`). **Não envia.**

- **Entrada**: `{ partner_id: integer, canal: whatsapp|email, texto: string (minLength 10) }`
- **Saída**: `{ rascunho_salvo: true, atividade_id, cliente, canal, aviso: "...nada foi enviado." }`

### `preparar_cotacao`
Salva rascunho de cotação (`outcome.tipo = "rascunho_cotacao"`): itens validados no catálogo,
com estoque de referência. **Sem preços** (fonte não integrada) e **sem tocar o ERP**.

- **Entrada**: `{ partner_id: integer, itens: [{ codigo: integer (CODPROD),
  quantidade: number > 0 }] (1..20) }`
- **Saída**: `{ rascunho_salvo: true, atividade_id, cliente, itens: [{ codigo, descricao,
  quantidade, estoque_snapshot? }], aviso }`
- **Erros**: produto fora do catálogo; quantidade inválida.

---

## O que NÃO existe (por construção)

Operações proibidas (doc 06) simplesmente **não têm ferramenta**: alterar preço, conceder
desconto, modificar crédito, faturar pedido, alterar meta, transferir carteira, enviar
comunicação externa. Pedido do modelo por qualquer capacidade fora da allowlist → erro.
