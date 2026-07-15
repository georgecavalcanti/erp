# Jatto — ERP / Força de Vendas 360

Plataforma de inteligência comercial da Jatto Distribuidora sobre o ERP Sankhya (fonte oficial dos dados; o Postgres local é espelho analítico).

## Projeto em andamento: Força de Vendas 360

O app atual (dashboard read-only de faturamento/carteira/inadimplência) está evoluindo para o **Força de Vendas 360**: cockpit orientado à meta, motores analíticos (projeção, recompra, priorização) e agente Claude.

➡️ **Toda a especificação e o plano de execução estão em [`docs/forca-de-vendas-360/`](docs/forca-de-vendas-360/README.md).** Para executar, siga [`docs/forca-de-vendas-360/10-plano-de-execucao.md`](docs/forca-de-vendas-360/10-plano-de-execucao.md) (fases, sprints, critérios de aceite — marque os checkboxes ao concluir).

## Stack

- Ruby 3.3.4 · Rails 8.1 · PostgreSQL 17 · Solid Queue (jobs+cron dentro do Puma, sem Redis)
- Inertia.js + Vue 3 + TypeScript + Tailwind 4 + ECharts (frontend em `app/frontend/`)
- Integração Sankhya via API Gateway (OAuth2 + X-Token) em `app/services/sankhya/` — somente leitura, SQL via `DbExplorerSP.executeQuery`
- Deploy: Railway (Dockerfile, healthcheck `/up`)

## Comandos

```bash
docker compose up -d      # Postgres local (porta 5433)
bin/dev                   # Rails :3100 + Vite :3136
bin/ci                    # suíte completa: testes + rubocop + brakeman + bundler-audit
bin/rails test            # só testes
```

## Convenções do projeto

- Idioma: **português** em rotas, telas, commits e comentários. Comentários densos explicando regra de negócio (manter o padrão).
- Fluxo: `Controller → Service → render inertia: "Pagina" → app/frontend/pages/Pagina.vue`.
- Dados do ERP: dimensões com `external_code`, fatos com `external_uid`, coluna `raw jsonb` com a linha original; upsert para histórico, snapshot atômico para estado; todo sync registra em `sync_runs`.
- Filtros de relatório: concern `app/controllers/concerns/analytics_filters.rb`.
- Regras de sync/reconcile: `docs/sankhya-sync-runbook.md`.

## Cuidados

- `Sankhya::Client` é read-only por design — não adicionar escrita no ERP.
- Campo `commission` existe mas é sempre 0 (cálculo ficará para módulo futuro).
- Empresa CODEMP 1 = Jatto (incluída); CODEMP 2 = Papel Leão (excluída dos syncs).
- `paid`/`paid_at` em invoices é marcação manual — o sync preserva.
- O agente Claude (quando implementado) nunca recebe credenciais do Sankhya e toda ferramenta é escopada pela carteira do usuário (`docs/forca-de-vendas-360/06-agente-claude.md`).
