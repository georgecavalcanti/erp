# 08 — Telas e Experiência do Usuário

Princípios: **mobile-first**, ação antes de relatório, explicabilidade, resiliência sem IA. Reaproveitar componentes existentes (`KpiCard`, `ChartCard`, `BaseChart`, `FilterBar`, `RankingReport`, `StatusBadge`, `Pagination`, `MultiSelect`) e o padrão Inertia atual.

## Novas páginas (`app/frontend/pages/`)

### 11.1 Cockpit do vendedor (`Cockpit.vue`) — nova home do perfil vendedor

- Meta, realizado, atingimento e **meta esperada até o dia**;
- Projeção conservadora, provável e potencial;
- Gap e **ritmo diário necessário**;
- Margem e clientes ativos/em risco;
- Resumo do Claude, ações do dia e alertas críticos.

Rota: `/cockpit` (root para vendedor/representante; gestor mantém dashboard atual).

### 11.2 Plano do dia (`DailyPlan.vue`)

Lista priorizada (saída do motor de priorização, interpretada pelo agente). Cada ação exibe:

| Campo | Descrição |
|---|---|
| Cliente e prioridade | Conta selecionada e nível de urgência |
| Motivo | Recompra, cotação, risco, queda, cross-sell ou oportunidade |
| Potencial | Valor e margem estimados |
| Canal | Ligação, WhatsApp, visita, e-mail ou tarefa interna |
| Abordagem | Produto, argumento e próximo passo sugerido |
| Ações | Concluir, adiar, descartar, registrar resultado ou abrir o cliente 360 |

Rota: `/plano-do-dia`.

### 11.3 Minha carteira (`Wallet.vue`)

Clientes segmentados por status (chips/filtros): **Saudáveis · Em expansão · Em atenção · Em risco · Inativos · Novos em ativação · Recompra próxima ou atrasada · Cotação aberta · Sem contato**. Busca, ordenação por potencial/receita, acesso ao Cliente 360.

Rota: `/minha-carteira`.

### 11.4 Cliente 360 (`Customer360.vue`)

- Identificação, contatos, segmento, cidade e responsável;
- Receita, margem, ticket, frequência, mix e evolução mensal;
- Produtos comprados, abandonados e oportunidades de cross-sell;
- Pedidos, crédito, ocorrências e histórico de relacionamento;
- Recompra prevista, risco, prioridade e recomendações do Claude;
- Registro rápido de atividade (contato/visita/observação).

Rota: `/clientes/:id`.

### 11.5 Copiloto (`Copilot.vue`)

Chat com o agente (doc 06). Streaming da resposta, recomendações renderizadas no formato padrão (cards com diagnóstico/evidências/impacto/confiança/próxima ação), botões de aceitar/adiar/descartar que atualizam `recommendations`. Estado degradado visível quando IA indisponível.

Rota: `/copiloto`.

### Dashboard do gestor (`ManagerDashboard.vue`)

- Equipe: meta × realizado × projeção por vendedor (evolução do `/situacao` atual);
- Desvios e alertas (vendedores em risco de meta, carteiras sem atualização);
- Acurácia das projeções e recompras; recomendações úteis vs. descartadas;
- Receita influenciada;
- Administração: metas, carteiras (transferências), pesos do score.

Rota: `/gestor` (+ subtelas de administração).

## Ajustes nas telas existentes

- Todas as páginas atuais passam a respeitar o **escopo de carteira** (doc 07) — para vendedor, "Dashboard/Carteira/Inadimplência" já vêm filtrados.
- `AppLayout.vue`: navegação condicionada ao perfil; indicador de último sync mantido; adicionar indicador de estado do agente.
- Rotas em português, seguindo o padrão atual (`/carteira`, `/inadimplencia`…).

## Mobile / PWA

- Layout responsivo Tailwind (mobile-first nas telas novas; revisar as existentes);
- Completar PWA: service worker para cache de shell + manifest existente (`app/views/pwa/`);
- Alvos de toque adequados nas ações do plano do dia (concluir/adiar/descartar com um toque).

## Resiliência (princípio do PDF)

Dados e indicadores básicos permanecem acessíveis mesmo com Claude indisponível: Cockpit, Plano do dia (última priorização persistida), Carteira e Cliente 360 funcionam 100% sem IA. Apenas o Copiloto e os textos de "resumo do Claude" degradam.
