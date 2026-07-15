# 04 — Modelo de Dados

Convenções existentes a manter: dimensões espelhadas com `external_code` único; fatos com `external_uid`; coluna `raw jsonb` com a linha original do ERP; timestamps Rails; FKs com índices.

## Tabelas existentes (manter/estender)

| Tabela | Situação | Mudanças planejadas |
|---|---|---|
| `companies` | OK | — |
| `partners` | Estender | + `cnpj`, `city`, `state`, `segment`, `situation`, `credit_limit`, `credit_blocked`, `region` |
| `salespeople` | Estender | + `active`, `email` (para vínculo com usuário) |
| `invoices` | Estender | + `total_cost`, `margin_value`, `margin_percent` (derivados dos itens); manter `commission` |
| `pending_orders` | **Evoluir para `orders`** | Histórico persistente (upsert por NUNOTA) com `status` (pending/billed/canceled/blocked), em vez de snapshot só do mês corrente. Manter view/scope "carteira" = pedidos pendentes |
| `overdue_titles`, `delinquencies` | OK | Alimentam risco/restrições dos motores |
| `users`, `sessions` | Estender | Ver RBAC abaixo |
| `sync_runs` | OK | Novos `kind` para os novos syncs |
| `import_batches` | Legado | Não usar em código novo |

## Novas tabelas — espelho do ERP

### `products`
`external_code` (CODPROD, único) · `description` · `category_external_code` · `category_name` (grupo TGFGRU) · `unit` · `brand` · `active` · `current_cost` (decimal) · `raw jsonb`

### `invoice_items`
`invoice_id` FK · `product_id` FK · `external_sequence` (SEQUENCIA; único com invoice) · `quantity` · `unit_price` · `discount` · `total_value` · `unit_cost` · `margin_value` · `raw jsonb`

### `order_items`
Mesma estrutura de `invoice_items`, FK para `orders`.

### `orders` (evolução de `pending_orders`)
Campos atuais + `status` enum · `billed_at` · `canceled_at` · `blocked` boolean · `raw jsonb`. Migração: renomear/migrar dados do snapshot atual.

### `stock_levels`
`product_id` FK · `company_id` FK · `available` · `reserved` · `synced_at` — snapshot (delete+insert atômico, padrão do `PendingOrderSync` atual).

### `partner_financials` (snapshot de crédito)
`partner_id` FK · `credit_limit` · `open_amount` · `overdue_amount` · `blocked` · `synced_at`

## Novas tabelas — núcleo comercial

### `wallets` (Carteira)
Vínculo vendedor↔cliente com vigência.
`salesperson_id` FK · `partner_id` FK · `responsibility_type` enum (`owner`, `contractual`, `temporary`) · `region` · `starts_on` · `ends_on` (null = vigente) · unique index (partner_id, vigência ativa)

> Regra: um vendedor não visualiza clientes, vendas ou recomendações de outra carteira sem autorização explícita.

### `goals` (Meta)
`salesperson_id` FK · `period` (date, 1º dia do mês) · `kind` enum (`revenue`, `margin`, `mix`, `activation`) · `amount` · `min_margin_percent` · `complementary jsonb` · `created_by_id` FK users · unique (salesperson, period, kind)

### `projections` (Projeção — versionada)
`salesperson_id` FK · `reference_date` · `scenario` enum (`conservative`, `likely`, `potential`) · `value` · `margin_value` · `confidence` (0–100) · `components jsonb` (parcelas rastreáveis: faturado, pedidos confirmados, pendentes ponderados, recompras, cotações, expansão…) · `method` · `engine_version` · append-only (nunca sobrescrever — auditoria)

### `repurchase_predictions` (Previsão de recompra — versionada)
`partner_id` FK · `level` enum (`customer`, `category`, `product`) · `product_id`/`category_external_code` (conforme nível) · `expected_date` · `expected_value` · `expected_quantity` · `confidence` · `method` · `engine_version` · `status` enum (`open`, `confirmed`, `missed`, `canceled`) · `confirmed_invoice_id` (para aprendizado)

### `priorities` (Prioridade do dia)
`salesperson_id` FK · `partner_id` FK · `reference_date` · `score` · `score_factors jsonb` (cada fator com peso e valor) · `reasons jsonb` (recompra/cotação/risco/queda/cross-sell/oportunidade) · `potential_value` · `urgency` · `suggested_action` · `restrictions jsonb` · `valid_until` · `position` (ordem no plano)

### `recommendations` (Recomendação — formato padrão, doc 06)
`user_id` FK · `salesperson_id` FK · `partner_id` FK (opcional) · `diagnosis` · `recommendation` · `evidences jsonb` · `potential_impact jsonb` (receita/margem/retenção) · `confidence` · `next_action` · `channel` enum (`call`, `whatsapp`, `visit`, `email`, `internal`) · `deadline` · `restrictions jsonb` · `tools_used jsonb` · `agent_run_id` FK · `status` enum (`pending`, `accepted`, `postponed`, `discarded`, `done`) · `feedback` enum (`useful`, `not_useful`, null) · `feedback_notes`

### `activities` (Registro de atividades)
`user_id` FK · `salesperson_id` FK · `partner_id` FK · `kind` enum (`contact`, `visit`, `task`, `note`, `result`) · `channel` · `notes` · `occurred_at` · `recommendation_id` FK (opcional) · `outcome jsonb`

### `influenced_revenues` (Receita influenciada)
`recommendation_id` FK · `invoice_id` FK · `amount` · `linked_by` enum (`automatic`, `manual`) — base do indicador "receita influenciada" do piloto.

### `agent_runs` (Auditoria do agente)
`user_id` FK · `kind` enum (`copilot`, `daily_plan`, `simulation`, `batch`) · `prompt_summary` · `model` · `tools_called jsonb` (nome, parâmetros, duração de cada chamada) · `input_tokens` · `output_tokens` · `cost_estimate` · `latency_ms` · `status` enum (`ok`, `error`, `refused`, `invalid_schema`) · `error_detail` · `response_digest`

## RBAC (detalhes no doc 07)

### `users` (estender)
+ `role` enum (`vendedor`, `representante`, `coordenador`, `gestor_comercial`, `administrador`, `diretoria`) · + `salesperson_id` FK (obrigatório para vendedor/representante) · + `manager_id` FK users (coordenador da equipe) · + `active`

## Diagrama de relacionamentos (essência)

```
salespeople 1─n wallets n─1 partners
salespeople 1─n goals
salespeople 1─n projections
partners    1─n repurchase_predictions (→ products)
salespeople 1─n priorities n─1 partners
users       1─n recommendations n─1 partners
recommendations 1─n influenced_revenues n─1 invoices
users       1─n activities
users       1─n agent_runs
invoices    1─n invoice_items n─1 products
orders      1─n order_items   n─1 products
```

## Regra de auditoria (transversal)

> Toda projeção e recomendação deve registrar **parâmetros, dados de origem, método, versão, resultado, nível de confiança e resultado comercial posterior**. Por isso `projections`, `repurchase_predictions` e `recommendations` são append-only/versionadas, nunca atualizadas in-place em seus campos analíticos.

## Índices críticos (volumetria de 24 meses de itens)

- `invoice_items (invoice_id)`, `invoice_items (product_id)`, composto `(product_id, invoice_id)` para mix por cliente.
- `invoices (salesperson_id, negotiation_date)` — já coberto parcialmente; revisar com EXPLAIN após backfill.
- `priorities (salesperson_id, reference_date)`, `projections (salesperson_id, reference_date, scenario)`.
- `wallets (partner_id) WHERE ends_on IS NULL` — resolução rápida de "de quem é este cliente".
