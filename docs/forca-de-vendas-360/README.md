# Jatto Força de Vendas 360 — Documentação do Projeto

> Evolução do painel atual ("Jatto Dash") para uma **plataforma de inteligência comercial e gestão de carteiras**, integrada ao ERP Sankhya e operada por um agente Claude.
>
> Fonte: `Projeto_Jatto_Forca_de_Vendas_360.pdf` (v1.0, julho/2026) + análise do codebase existente.

## Propósito do sistema

Mostrar ao vendedor onde ele está, projetar onde chegará, identificar o que falta para sua meta e construir diariamente o melhor plano comercial para sua carteira.

## Como usar esta documentação

- **Vai executar?** Comece por [10-plano-de-execucao.md](10-plano-de-execucao.md) — é o plano mestre (fases, sprints, tarefas, critérios de aceite). Cada sprint referencia os documentos de especificação abaixo.
- **Precisa de contexto?** Leia na ordem 01 → 09.

## Índice

| Doc | Conteúdo |
|---|---|
| [01-visao-e-escopo.md](01-visao-e-escopo.md) | Visão do produto, objetivos estratégicos, escopo do MVP, critérios de aceite |
| [02-arquitetura.md](02-arquitetura.md) | ADR: evoluir o stack Rails atual; camadas da solução; regra central do agente |
| [03-integracao-sankhya.md](03-integracao-sankhya.md) | O que já existe, novos syncs, frequências, consultas em tempo real, carga inicial 24 meses |
| [04-modelo-de-dados.md](04-modelo-de-dados.md) | Tabelas existentes e novas, campos e relacionamentos |
| [05-motores-analiticos.md](05-motores-analiticos.md) | Motores de projeção, recompra, risco/queda/cross-sell, priorização e simulador |
| [06-agente-claude.md](06-agente-claude.md) | Ferramentas autorizadas, contratos, formato de recomendação, limites, custos, auditoria |
| [07-perfis-e-permissoes.md](07-perfis-e-permissoes.md) | RBAC, carteiras e isolamento de dados |
| [08-telas-e-ux.md](08-telas-e-ux.md) | Cockpit, Plano do dia, Minha carteira, Cliente 360, Copiloto, Dashboard do gestor |
| [09-seguranca-e-observabilidade.md](09-seguranca-e-observabilidade.md) | Segurança, LGPD, métricas técnicas e alertas |
| [10-plano-de-execucao.md](10-plano-de-execucao.md) | **Plano mestre**: fases, 10 sprints, testes obrigatórios, piloto e governança |

## Estado atual vs. destino (resumo)

**Já existe** (base sólida a reaproveitar):
- Integração Sankhya read-only via API Gateway (`app/services/sankhya/`): OAuth2, paginação keyset, sync incremental, reconcile, advisory lock, cron via Solid Queue.
- Espelho Postgres de: empresas, parceiros, vendedores, notas (venda/devolução), carteira a faturar, títulos inadimplentes.
- Painéis Inertia/Vue: Dashboard, Situação, Vendedores, Parceiros, Carteira, Inadimplência, Devoluções.
- Autenticação por sessão (Rails 8 nativo), deploy Railway dockerizado.

**A construir** (núcleo deste projeto):
- Produtos, itens de nota/pedido, estoque, custos/margem, preços, crédito (novos syncs + backfill 24 meses).
- Usuários com perfis, carteiras e isolamento por vendedor.
- Metas por vendedor/período.
- Motores: projeção (3 cenários), recompra, risco/queda/cross-sell, priorização, simulador de meta.
- Agente Claude com ferramentas controladas, copiloto e plano diário.
- Novas telas: Cockpit, Plano do dia, Minha carteira, Cliente 360, Copiloto, Dashboard do gestor.
- Registro de atividades, auditoria, receita influenciada e métricas de acurácia.

## Decisões arquiteturais finais (do documento executivo)

1. O Sankhya será a fonte oficial dos dados.
2. A aplicação não acessará diretamente o banco do ERP.
3. A integração utilizará o API Gateway e OAuth 2.0.
4. O sistema manterá uma base analítica própria.
5. O Claude será o agente central de análise e decisão.
6. O Claude utilizará ferramentas controladas e auditáveis.
7. Projeções, prioridades e recomendações serão versionadas.
8. Cada recomendação deverá ser explicável.
9. Escritas sensíveis no ERP exigirão autorização.
10. O MVP será orientado à carteira e à meta.
11. O sistema continuará consultável sem a disponibilidade temporária da IA.
12. O aprendizado ocorrerá pela comparação entre previsão, ação e resultado.
