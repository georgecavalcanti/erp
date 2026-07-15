# 10 — Plano de Execução (Plano Mestre)

> **Este é o documento de trabalho da execução.** Cada sprint lista objetivo, tarefas com arquivos, critérios de aceite e testes. Marque os checkboxes conforme concluir. Especificações detalhadas nos docs 02–09.

## Contexto

O repositório hoje é o "Jatto Dash" (BI read-only sobre o Sankhya). Este plano o evolui para o **Força de Vendas 360**: cockpit orientado à meta, motores analíticos e agente Claude, conforme `Projeto_Jatto_Forca_de_Vendas_360.pdf` (v1.0). Decisão de arquitetura: **evoluir o stack Rails existente** (ADR-001, doc 02).

## Fases (visão macro)

| Fase | Principais entregas | Sprints |
|---|---|---|
| 0. Diagnóstico técnico | Entidades Sankhya, TOPs, vendedores, carteiras, custos, margem, estoque, metas, customizações e credenciais | Pré-sprint |
| 1. Fundação de dados | Autenticação, carga inicial 24m, banco analítico, sincronização, logs e usuários | 1–3 |
| 2. Cockpit | Meta, realizado, margem, ritmo, projeção básica, gap e gestor | 4 |
| 3. Inteligência | Recompra, queda, risco, cross-sell, score e cliente 360 | 5–7 |
| 4. Agente Claude | Ferramentas, prompt institucional, copiloto, plano diário e simulador | 8 |
| 5. Piloto | 3 a 5 vendedores, 100 a 150 clientes, treinamento, validação e ajustes | 9–10 |
| 6. Expansão | Equipe direta, representantes, gestão regional e novos recursos | Pós-MVP |

---

## Fase 0 — Diagnóstico técnico (fazer antes da Sprint 1)

Sessão de trabalho com o responsável Sankhya (não é sprint de código):

- [x] Validar tabelas/campos reais: TGFPRO, TGFGRU, TGFITE, TGFEST, TGFCUS, TGFTAB/TGFEXC, crédito em TGFPAR (checklist no doc 03, seção Fase 0)
- [x] Confirmar TOPs de pedido/venda/devolução/cancelamento em uso — **descoberta: TOP 1000 = cotações (orçamentos de venda)**
- [x] Medir volumetria de itens — ~961 mil itens; **histórico real começa em dez/2024 (~19 meses, não 24)**
- [x] Confirmar permissões do usuário de integração (todas as tabelas acessíveis; rate limit: validar em produção contínua — pendência leve)
- [x] Levantar como metas e carteiras são geridas hoje — **TGFMET vazia (metas fora do ERP → geridas no FV360); carteiras via TGFPAR.CODVEND (81% preenchido)**
- [x] Registrar tudo em `docs/forca-de-vendas-360/fase-0-diagnostico.md`
- [x] Atualizar `README.md` do repo (remover menções ao import de planilha, refletir API-only)
- [ ] Pendências humanas de `fase-0-diagnostico.md` §13 (validações com gestor comercial — não bloqueiam Sprints 1–2)

**Aceite**: ✅ 15/07/2026 — queries de cada novo sync validadas no gateway de **produção** com dados reais. Decisões derivadas em `fase-0-diagnostico.md` (margem = `VLRTOT − VLRDESC − QTDNEG×CUSTO`; vendas por TOP explícita; crédito por inadimplência+bloqueio; cotações como nova entidade).

---

## Sprint 1 — Produtos, categorias e enriquecimento de cadastros

**Escopo PDF**: OAuth Sankhya ✔ (existe) · clientes ✔ (enriquecer) · vendedores ✔ · **produtos** (novo).

- [x] Migration + model `Product` (doc 04)
- [x] `Sankhya::ProductSync` (upsert por CODPROD; padrão do `InvoiceSync`)
- [x] Enriquecer `partners`: cnpj, cidade, UF, segmento, ativo/bloqueado, última negociação — via `Sankhya::PartnerSync` dedicado (todos os clientes, inclusive quem nunca comprou; `raw.CODVEND` pronto p/ seed de carteiras)
- [x] Campos `active`/`email`/`seller_kind` em `salespeople` — via `Sankhya::SalespersonSync`
- [x] `Sankhya::CatalogSync` (orquestrador + advisory lock próprio) + `SankhyaCatalogSyncJob` a cada 2h em `config/recurring.yml` + tasks `sankhya:products`, `sankhya:products_dry`, `sankhya:sync_catalog`
- [x] Testes: 12 testes de sync (mapeamento, idempotência, paginação keyset, linha inválida, dry-run) com `FakeSankhyaClient`
- [x] Extra: `partners.external_code` int4→bigint — 42 clientes reais com CODPARC de 10 dígitos eram pulados pelo sync (sem notas históricas perdidas; eram prospects sem compra)
- [x] Extra: consertados 3 testes legados de senha (assert_select em página Inertia) e ofensas rubocop pré-existentes — `bin/ci` 100% verde

**Aceite**: ✅ 15/07/2026 — catálogo 3.249/3.249 produtos espelhado (100% com categoria); 5.939/5.939 clientes com CNPJ/cidade/UF; 60 vendedores com tipo/ativo; `sync_runs` registrando ("Produtos/Parceiros/Vendedores"); `bin/ci` verde.

## Sprint 2 — Pedidos, itens, notas com itens, custos e margem

**Escopo PDF**: pedidos; itens; notas; cancelamentos; devoluções; custos.

Executada em duas partes: **2A** (itens+custo+margem, feita) e **2B** (pedidos com histórico + carteira, pendente).

### Parte 2A — Itens de nota, custo e margem ✅
- [x] Migration `invoice_items` + colunas `total_cost`/`margin_value`/`margin_percent`/`items_synced_at` em `invoices`
- [x] `InvoiceItem` model + associação em `Invoice` + `Invoice#signed_margin`
- [x] `Sankhya::CostSync` — custo atual do produto (TGFCUS.CUSGER, mais recente) → `Product#current_cost`
- [x] `Sankhya::InvoiceItemSync` — TGFITE, keyset composto (NUNOTA,SEQUENCIA), `upsert_all`, custo congelado (`TGFITE.CUSTO`), rollup de margem na nota via UPDATE...FROM
- [x] Incremental: etapa "Itens" no `ScheduledSync` (notas mexidas em 24h); custo diário no `CatalogSync`
- [x] Tasks `sankhya:items[dias]`, `items_dry`, `items_all` (backfill dez/2024), `costs`; `bootstrap` inclui itens
- [x] Testes: 9 (mapeamento de margem, keyset composto sem partir nota, órfão, custo ausente, idempotência, dry-run)
- [x] **Validação contra ERP produção**: 762 notas / 7.991 itens (7 dias); conciliação `Σ net_value` = `VLRNOTA` → **0 divergências**; margens 22–30%

### Parte 2B — Pedidos com histórico e carteira (pendente)
- [ ] Migrations: `orders` (evolução de `pending_orders` com status/histórico), `order_items`
- [ ] `Sankhya::OrderSync` — histórico com status (pendente/faturado/cancelado/bloqueado), upsert por NUNOTA
- [ ] Itens de pedido via `ItemSync` (generalizar o de notas)
- [ ] Backfill de pedidos + itens desde dez/2024
- [ ] Ajustar frequências: pedidos 10 min, notas/devoluções 15 min (doc 03)
- [ ] Migrar telas Carteira/Devoluções para `orders` (view carteira = pendentes)
- [ ] Índices de volumetria (doc 04) + EXPLAIN nas consultas de mix
- [ ] Testes: transição de status do pedido, reconcile de itens

**Aceite**: ✅ (2A) faturamento e margem por nota conferem com o Sankhya (0 divergências em amostra). Falta backfill completo dos 19 meses (rodar `sankhya:items_all` fora do horário) + validação do gestor; **2B** conclui pedidos/carteira.

## Sprint 3 — Usuários, perfis, carteiras, metas e indicadores básicos

**Escopo PDF**: autenticação ✔ · **permissões; carteiras; metas; indicadores básicos**.

- [ ] Migration `users`: role, salesperson_id, manager_id, active
- [ ] Migrations `wallets` + `goals` (doc 04)
- [ ] Policies de escopo (`authorized_salesperson_ids` / `authorized_partner_ids`) + integração no `analytics_filters.rb` (doc 07)
- [ ] Carga inicial de carteiras a partir do CODVEND do parceiro no Sankhya
- [ ] CRUD de usuários, carteiras e metas (telas de administração, perfil gestor/admin)
- [ ] Aplicar escopo às telas existentes (Dashboard, Situação, Carteira, Inadimplência…)
- [ ] Navegação por perfil no `AppLayout.vue`
- [ ] **Testes de segurança: isolamento entre vendedores** (vendedor A nunca vê dados de B) — obrigatório
- [ ] Convite/criação de usuários vendedores (sem auto-registro)

**Aceite**: critérios MVP 3 e 4 (isolamento de carteira; meta vinculada a vendedor/período corretos).

## Sprint 4 — Cockpit: realizado, ritmo, gap e cenários

**Escopo PDF**: cockpit; realizado; ritmo; gap; cenários.

- [ ] Calendário de dias úteis (feriados BR) — utilitário compartilhado
- [ ] `Engines::Projection` (3 cenários com `components jsonb`, doc 05.1) + tabela `projections`
- [ ] Job de recálculo (a cada sync relevante + virada de dia)
- [ ] Página `Cockpit.vue` (doc 08): meta, realizado, atingimento vs. esperado, projeções, gap, ritmo diário
- [ ] Root por perfil: vendedor → `/cockpit`; gestor → dashboard atual
- [ ] Testes de cálculo: faturamento líquido, devoluções, dias úteis, cenários (fixtures determinísticas)

**Aceite**: critérios MVP 1, 2 e 5 (faturamento = Sankhya; devoluções corretas; projeção com componentes rastreáveis e confiança).

## Sprint 5 — Cliente 360: frequência, mix, margem e financeiro

**Escopo PDF**: cliente 360; frequência; mix; margem; financeiro.

- [ ] `Sankhya::StockSync` + `Sankhya::CreditSync` + `partner_financials` (doc 03/04)
- [ ] `Sankhya::LiveQueries` (estoque, preço, crédito, situação de pedido em tempo real com fallback)
- [ ] Serviço `Customer360Report`: receita, margem, ticket, frequência, mix por categoria, evolução mensal
- [ ] Página `Customer360.vue` (doc 08) com registro rápido de atividade
- [ ] Migration `activities` + registro de contato/visita/observação
- [ ] Página `Wallet.vue` (Minha carteira) com segmentação básica (sem status de risco ainda)
- [ ] Testes: agregações do 360 (frequência, mix), fallback das consultas tempo real

**Aceite**: vendedor abre qualquer cliente da sua carteira e vê o 360 completo em < 2s (dados locais) com crédito/estoque ao vivo.

## Sprint 6 — Recompra, confiança e alertas

**Escopo PDF**: modelo inicial de recompra; confiança; alertas.

- [ ] `Engines::Repurchase` estágio estatístico (doc 05.2) + tabela `repurchase_predictions`
- [ ] Job noturno de previsão em lote (madrugada)
- [ ] Confirmação automática: compra real → `status=confirmed` + `confirmed_invoice_id`; expiração → `missed`
- [ ] `Engines::Risk` + `Engines::ConsumptionDrop` (doc 05.3) → status da carteira
- [ ] Status de risco na `Wallet.vue` (chips: saudável/atenção/risco/inativo/recompra atrasada…)
- [ ] Tabela `alerts` + `Alerts::ScanJob` (integração, dados, conciliação, negócio — doc 09)
- [ ] Testes: previsão com históricos sintéticos (regular, irregular, sazonal), transições de status

**Aceite**: critério MVP 6 (recompra com data, valor e confiança); recompras atrasadas aparecem na carteira.

## Sprint 7 — Priorização, plano diário e registro de resultados

**Escopo PDF**: score; restrições; plano diário; registro de resultados.

- [ ] `Engines::CrossSell` (doc 05.3)
- [ ] `Engines::Prioritization`: score com pesos configuráveis, restrições, estratégias adaptativas (doc 05.4) + tabela `priorities`
- [ ] Configuração de pesos e capacidade diária (tela do gestor)
- [ ] `Engines::GoalSimulator` (heurística de combinação, doc 05.5)
- [ ] Página `DailyPlan.vue`: ações com motivo/potencial/canal/abordagem + concluir/adiar/descartar/registrar resultado
- [ ] Migrations `recommendations` (estrutura) + `influenced_revenues`; registrar resultado vincula venda
- [ ] Testes: score (pesos), aplicação de restrições, estratégia por posição vs. meta, capacidade respeitada

**Aceite**: critérios MVP 7, 8 e 11 (prioridade com motivo/potencial/restrições; plano respeita capacidade; ação e resultado registrados).

## Sprint 8 — Agente Claude: ferramentas, orquestração e copiloto

**Escopo PDF**: ferramentas Claude; orquestração; saídas estruturadas; copiloto.

- [ ] `Agent::ToolRegistry` + as ~24 ferramentas dos 3 grupos com JSON Schema (doc 06) — **escrever os contratos JSON como artefato desta sprint**
- [ ] `Agent::ContextBuilder` (contexto institucional cacheável + posição do vendedor)
- [ ] `Agent::Orchestrator`: loop de tool use, structured output do formato de recomendação, persistência em `recommendations` + `agent_runs`
- [ ] Prompt caching + seleção de modelo por complexidade + teto diário de tokens (doc 06, custos)
- [ ] Página `Copilot.vue` com streaming e cards de recomendação (aceitar/adiar/descartar)
- [ ] "Resumo do Claude" no Cockpit e abordagens no Plano do dia gerados pelo agente
- [ ] Degradação sem IA (última resposta válida + aviso)
- [ ] Testes: uso correto das ferramentas (mock da API), dados conflitantes, ausência de dados (não inventa), esquema inválido (retry + status), ações não autorizadas inexistentes no registry

**Aceite**: critérios MVP 9 e 13 (só ferramentas autorizadas, não inventa dados; indisponibilidade da IA não impede consulta). Os 5 casos de uso do copiloto (doc 06) funcionam.

## Sprint 9 — Dashboard do gestor, auditoria, acurácia e receita influenciada

**Escopo PDF**: dashboard do gestor; auditoria; acurácia; receita influenciada.

- [ ] `ManagerDashboard.vue`: equipe (meta × realizado × projeção), desvios, alertas (doc 08)
- [ ] Métricas de acurácia: projeções (previsto × realizado) e recompras (confirmadas/perdidas)
- [ ] Recomendações: úteis × descartadas por vendedor; receita influenciada (via `influenced_revenues`)
- [ ] Tela de auditoria (admin): `agent_runs` (custo, tokens, ferramentas), `sync_runs`, `alerts`
- [ ] Exportações controladas e registradas (doc 09)
- [ ] Revisão de performance (índices, N+1, caching de agregações)
- [ ] Testes: agregações do gestor, cálculo de receita influenciada

**Aceite**: critério MVP 10 (gestor acompanha equipe e desvios); custo do agente visível por dia/usuário.

## Sprint 10 — Piloto: treinamento, testes e liberação controlada

**Escopo PDF**: piloto; treinamento; testes; feedback; liberação controlada.

- [ ] Ambiente de homologação no Railway (doc 02)
- [ ] Plano do piloto: selecionar 3–5 vendedores e 100–150 clientes; linha de base dos indicadores (doc abaixo); metas carregadas
- [ ] Checklist completo dos 14 critérios de aceite do MVP (doc 01) executado e evidenciado
- [ ] Revisão mobile/PWA de todas as telas do vendedor
- [ ] Testes de carga do sync nas novas frequências
- [ ] `bin/ci` verde: suíte completa + brakeman + rubocop
- [ ] Treinamento dos vendedores (roteiro + sessão) e canal de feedback
- [ ] Liberação controlada em produção (flag por usuário piloto)
- [ ] Rotina semanal de acompanhamento dos indicadores do piloto

**Aceite**: piloto rodando em produção com os 3–5 vendedores; indicadores medidos semanalmente.

---

## Testes obrigatórios (transversal — PDF seção 18)

| Categoria | Testes |
|---|---|
| Integração | Autenticação, expiração de token, paginação, timeout, duplicidade, incremental e reconciliação |
| Cálculos | Faturamento, margem, devoluções, dias úteis, cenários, recompra e prioridade |
| Segurança | Isolamento entre vendedores, elevação de privilégio, segredos, exportações e logs |
| Claude | Uso correto das ferramentas, dados conflitantes, ausência de dados, esquema inválido e ações não autorizadas |
| Usabilidade | Mobile, localização de cliente, registro de atividade, clareza e carga diária de ações |

Ferramentas: Minitest (unit/integration), Capybara/Selenium (system), fixtures de payloads Sankhya, mock da Claude API. A suíte atual é esqueleto — cada sprint entrega os testes do que construiu.

## Indicadores de sucesso do piloto (PDF seção 20)

| Indicador | Objetivo inicial |
|---|---|
| Vendedores ativos semanalmente | > 90% |
| Ações concluídas | > 75% |
| Projeções dentro da faixa esperada | > 80% |
| Alertas de recompra confirmados | > 65% |
| Recomendações consideradas úteis | > 70% |
| Clientes sem contato | Redução de 25% |
| Tempo de preparação comercial | Redução de 30% |
| Receita influenciada | Mensurada e crescente |
| Margem das vendas sugeridas | ≥ média |

## Governança do produto (PDF seção 21)

| Papel | Responsabilidades |
|---|---|
| Product Owner | Prioridades, regras comerciais, aceite e comunicação com a equipe |
| Responsável Sankhya | Entidades, campos, TOPs, permissões, APIs e validação dos dados |
| Gestor comercial | Metas, carteiras, critérios de prioridade e validação das recomendações |
| Equipe técnica | Desenvolvimento, dados, integrações, segurança e monitoramento |
| Comitê de IA | Limites, qualidade, custo, segurança, prompts e ferramentas |

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Tabelas/TOPs do Sankhya diferentes do assumido | Fase 0 valida tudo antes de codificar; queries parametrizadas por config |
| Volumetria de TGFITE (24m) maior que o esperado | Backfill em lotes na madrugada; índices planejados; medir na Fase 0 |
| Rate limit do gateway nas frequências de 10 min | Confirmar limites na Fase 0; backoff já existe no `Client`; degradar frequência se preciso |
| Custo do agente acima do previsto | Estratégia de custos (doc 06) + teto diário + auditoria em `agent_runs` desde a Sprint 8 |
| Qualidade das previsões no início | Estágio estatístico transparente + confiança exibida + aprendizado por comparação; expectativa gerida no treinamento |
| Dados de carteira/meta inexistentes no ERP | Levantamento na Fase 0; telas de administração na Sprint 3 permitem gestão manual |

## Definição de pronto (por sprint)

1. Código com testes das categorias tocadas passando (`bin/ci`);
2. Critérios de aceite do sprint verificados com dados reais (sandbox ou produção);
3. Checkboxes deste documento atualizados;
4. Sem regressão nas telas existentes (smoke manual: Dashboard, Situação, Carteira, Inadimplência).

## Artefatos a produzir durante a execução (PDF seção 23)

- [ ] `fase-0-diagnostico.md` — mapeamento real de entidades, campos e TOPs (Fase 0)
- [ ] Contratos JSON das ferramentas do Claude (Sprint 8, em `docs/forca-de-vendas-360/contratos-ferramentas.md`)
- [ ] Plano do piloto com carteiras, usuários, linha de base e metas (Sprint 10)
- [ ] Wireframes das telas — opcional, direto em Vue seguindo doc 08
