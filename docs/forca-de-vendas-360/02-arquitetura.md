# 02 — Arquitetura

## ADR-001: Evoluir o stack Rails existente (não reescrever)

**Status**: aceita · **Data**: 2026-07-15

### Contexto

O documento executivo **sugere** (seção 3.2) Next.js/React no frontend, Node.js/NestJS no backend, Redis para cache/filas. O projeto atual, porém, já é um monolito **Rails 8.1 + Inertia.js + Vue 3 + TypeScript + Tailwind 4 + PostgreSQL 17**, com:

- Camada de integração Sankhya madura (`app/services/sankhya/`): OAuth2 client-credentials, `X-Token`, paginação keyset, encoding ISO-8859-1, sync incremental por `DTALTER`, reconcile com advisory lock, histórico em `sync_runs`.
- Espelho analítico funcionando (invoices, pending_orders, overdue_titles, partners, salespeople, companies).
- Solid Queue (jobs + cron dentro do Puma, sem Redis) e deploy Railway dockerizado com healthcheck.

### Decisão

Evoluir o app Rails existente. Os requisitos do documento são todos atendíveis pelo stack atual:

| Requisito do PDF | Como o stack atual atende |
|---|---|
| Interface PWA responsiva mobile-first | Vue 3 + Tailwind; manifest PWA já existe em `app/views/pwa/` |
| Backend tipado com serviços | Services Ruby (`app/services/`), frontend em TypeScript |
| Banco principal PostgreSQL | Já é PostgreSQL 17 |
| Cache e filas / processamento assíncrono | Solid Queue (já em uso) + Solid Cache/Rails cache; Redis só se provar necessário |
| Integração via API Gateway oficial + OAuth 2.0 | `Sankhya::Client` já implementa exatamente isso |
| Claude API com tool use e saídas estruturadas | SDK Ruby da Anthropic (ou HTTP via `net/http`, padrão já usado no `Sankhya::Client`) |
| Observabilidade | Logs Rails estruturados + tabelas `sync_runs`/`agent_runs` + alertas (doc 09) |
| Ambientes segregados | Railway (produção) + dev local; homologação a criar no Railway |

### Consequências

- Nenhuma migração de framework; todo o esforço vai para funcionalidade.
- Equipe/manutenção em um único codebase e um único deploy.
- Previsões pesadas em lote rodam via Solid Queue fora do horário comercial (config em `config/recurring.yml`).
- Se o volume de jobs exigir, extrair worker dedicado (`SOLID_QUEUE_IN_PUMA=false`) antes de considerar Redis.

## Camadas da solução

| Camada | Responsabilidade | Onde vive no codebase |
|---|---|---|
| 1. Sankhya ERP | Fonte oficial: clientes, vendedores, produtos, pedidos, notas, estoque, custos, preços, crédito e financeiro | Externo (API Gateway) |
| 2. Integração Jatto | Autenticação, extração, validação, normalização, sincronização incremental e monitoramento | `app/services/sankhya/` |
| 3. Base comercial | Histórico consolidado, metas, indicadores, previsões, prioridades e recomendações | PostgreSQL (`db/schema.rb`, doc 04) |
| 4. Ferramentas analíticas | Projeção, recompra, risco, cross-sell, priorização, simulação e otimização | `app/services/engines/` (novo) |
| 5. Agente Claude | Seleciona ferramentas, interpreta resultados, simula cenários, cria planos e explica decisões | `app/services/agent/` (novo) |
| 6. Aplicação Jatto 360 | Cockpit, plano do dia, cliente 360, copiloto e dashboard do gestor | Controllers Inertia + `app/frontend/pages/` |

## Regra central

> **O Claude não recebe credenciais do Sankhya e não acessa diretamente o ERP.** Ele chama ferramentas internas autenticadas, com parâmetros e permissões controlados pela aplicação.

Implicações práticas:

- As ferramentas do agente (doc 06) são classes Ruby que consultam **a base comercial local** ou, quando necessário dado rigorosamente atualizado, o `Sankhya::Client` — sempre no servidor, nunca expondo credenciais ao modelo.
- Toda chamada de ferramenta é escopada pela carteira do usuário autenticado (doc 07) e registrada para auditoria (`agent_runs`, doc 04).
- O agente nunca executa escrita no ERP. Ações preparadas (mensagem, cotação) ficam em rascunho aguardando aprovação humana.

## Fluxo de renderização (padrão existente, manter)

```
Controller → Service (Analytics / Engines / Agent) → render inertia: "Pagina" → app/frontend/pages/Pagina.vue
```

- Filtros compartilhados via concern `app/controllers/concerns/analytics_filters.rb` (estender com escopo de carteira).
- Gráficos com ECharts via `app/frontend/components/BaseChart.vue`.
- Auto-refresh com `usePoll` (30s) já usado no `AppLayout.vue`.

## Ambientes

| Ambiente | Infra | Observação |
|---|---|---|
| Desenvolvimento | Local: `bin/dev` (Rails :3100 + Vite :3136), Postgres via `docker-compose` (porta 5433) | Sandbox Sankhya (`SANKHYA_BASE_URL` default) |
| Homologação | Railway (novo serviço, a criar na Fase 1) | Sandbox Sankhya + Claude com chave de teste |
| Produção | Railway (existente), Dockerfile multi-stage, healthcheck `/up` | Sankhya produção; segredos no vault do Railway |

## Novas variáveis de ambiente

Além das existentes (`DATABASE_URL`, `RAILS_MASTER_KEY`, `SANKHYA_*`, `ADMIN_*`):

| Variável | Uso |
|---|---|
| `ANTHROPIC_API_KEY` | Agente Claude (nunca exposta ao cliente) |
| `CLAUDE_MODEL_DEFAULT` | Modelo padrão do copiloto/planos (ex.: `claude-sonnet-5`) |
| `CLAUDE_MODEL_LIGHT` | Modelo econômico para tarefas simples (ex.: `claude-haiku-4-5-20251001`) |
| `AGENT_DAILY_TOKEN_BUDGET` | Teto diário de tokens do agente (controle de custo) |
