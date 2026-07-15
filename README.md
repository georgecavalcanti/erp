# Jatto — Plataforma Comercial (ERP / Força de Vendas 360)

Plataforma de inteligência comercial da Jatto Distribuidora sobre o ERP Sankhya:
espelho analítico em Postgres sincronizado via API Gateway (somente leitura),
painéis de faturamento, carteira e inadimplência — **em evolução para o
[Força de Vendas 360](docs/forca-de-vendas-360/README.md)** (cockpit orientado à
meta, motores analíticos e agente Claude).

## Stack

- **Ruby on Rails 8.1** + Ruby 3.3
- **PostgreSQL 17** (Docker isolado) · **Solid Queue** (jobs + cron no Puma, sem Redis)
- **Vite + Inertia.js + Vue 3 + TypeScript**
- **Tailwind CSS 4** · **ECharts** (gráficos)
- Autenticação nativa do Rails 8
- Integração **Sankhya API Gateway** (OAuth2 + X-Token) em `app/services/sankhya/`

## Requisitos

- Ruby 3.3, Node 20+, Docker

## Setup

```bash
# 1. Banco (Postgres isolado na porta 5433)
docker compose up -d

# 2. Dependências
bundle install
npm install

# 3. Banco + admin
bin/rails db:prepare   # cria + migra
bin/rails db:seed      # cria o admin
```

Admin padrão (troque em produção via `ADMIN_EMAIL` / `ADMIN_PASSWORD`):

- **e-mail:** `admin@faturamento.local`
- **senha:** `faturamento123`

Credenciais do Sankhya via ambiente (`.env` local, vault no Railway):
`SANKHYA_CLIENT_ID`, `SANKHYA_CLIENT_SECRET`, `SANKHYA_X_TOKEN`, `SANKHYA_BASE_URL`.

## Rodando

```bash
bin/dev            # sobe Rails (:3100) + Vite (:3136)
bin/ci             # testes + rubocop + brakeman + bundler-audit
```

Acesse http://localhost:3100.

> As portas (Postgres **5433**, web **3100**, Vite **3136**) foram escolhidas
> para não conflitar com outros projetos que usam 5432/3000/3036.

## Sincronização com o Sankhya

Os dados vêm da API oficial (SQL somente leitura via `DbExplorerSP.executeQuery`):

- **Notas** (vendas TOP 1101, devoluções 1201/1202): upsert incremental por
  `NUNOTA`/`DTALTER` — histórico preservado.
- **Carteira** (pedidos TOP 1001 pendentes) e **inadimplência** (títulos
  vencidos): snapshot atômico.
- Cron (produção): sync a cada 30 min (8h–19h) + reconciliação noturna.
- Todo sync registra em `sync_runs` (visível no cabeçalho da UI).

Detalhes operacionais: [`docs/sankhya-sync-runbook.md`](docs/sankhya-sync-runbook.md).

## Arquitetura

```
app/
  models/         Company, Partner, Salesperson, Invoice, PendingOrder,
                  OverdueTitle, Delinquency, SyncRun, User/Session
  services/
    sankhya/      client, config, invoice_sync, pending_order_sync,
                  overdue_title_sync, reconcile, scheduled_sync
    analytics.rb  + *_report.rb (agregações por tela)
  controllers/    dashboard, situation, salespeople, partners, portfolio,
                  receivables, returns + concerns/analytics_filters
  frontend/
    pages/        Dashboard, Situation, Salespeople, Partners, Portfolio,
                  Receivables, Returns, auth/Login
    components/   FilterBar, KpiCard, ChartCard, BaseChart, RankingReport, ...
    layouts/      AppLayout
```

Fluxo padrão: `Controller → Service → render inertia: "Pagina" → pages/Pagina.vue`.

### Conceitos-chave

- **Faturamento líquido** = vendas − devoluções (cada nota tem `signed_value`).
- **Vencimento** derivado do prazo de negociação; à vista = data da negociação.
- **Inadimplência** oficial vem do ERP (`overdue_titles`); `paid`/`paid_at` em
  invoices é marcação manual preservada pelo sync.
- **Extensível**: cada registro espelhado guarda a linha original em `raw`
  (jsonb) — novas visualizações não exigem novo fetch.

## Força de Vendas 360 (em construção)

Especificação completa e plano de execução por sprints em
[`docs/forca-de-vendas-360/`](docs/forca-de-vendas-360/README.md) — comece por
[`10-plano-de-execucao.md`](docs/forca-de-vendas-360/10-plano-de-execucao.md).
Diagnóstico real do ERP (TOPs, volumetria, campos):
[`fase-0-diagnostico.md`](docs/forca-de-vendas-360/fase-0-diagnostico.md).

## Deploy

Railway (Dockerfile multi-stage, healthcheck `/up`). Produção usa `DATABASE_URL`
e roda `db:prepare` no entrypoint.
