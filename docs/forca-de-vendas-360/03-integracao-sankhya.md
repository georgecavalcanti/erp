# 03 — Integração com o Sankhya

## Princípios (do documento executivo, seção 4.1)

- Utilizar exclusivamente as APIs oficiais e o Gateway de Integrações.
- Evitar acesso direto ao banco do ERP.
- Manter credenciais somente no servidor, em cofre de segredos.
- Isolar a integração em um serviço independente da interface do vendedor.
- Implementar paginação, retentativas, reconciliação e detecção de duplicidades.
- Registrar a origem e o horário de atualização de cada dado crítico.

> Todos já são práticas do código atual (`app/services/sankhya/client.rb`, `docs/sankhya-sync-runbook.md`). Os novos syncs devem seguir os mesmos padrões: upsert por chave externa para dados históricos, snapshot atômico para dados de estado, `sync_runs` para rastreio.

## O que já existe

| Sync | Fonte Oracle | Estratégia | Frequência atual |
|---|---|---|---|
| `Sankhya::InvoiceSync` | TGFCAB (TOPs 1101 venda, 1201/1202 devolução), empresa 1 | Upsert por NUNOTA; incremental por DTALTER; backfill; reconcile | 30 min (8h–19h) |
| `Sankhya::PendingOrderSync` | TGFCAB (TOP 1001 pendentes) | Snapshot atômico | 30 min |
| `Sankhya::OverdueTitleSync` | TGFFIN (boletos/PIX vencidos em aberto) | Snapshot + resumo derivado | 30 min |
| Dimensões (partners, salespeople, companies) | TGFPAR, TGFVEN, TSIEMP | Upsert junto aos syncs de fatos | — |
| `Sankhya::Reconcile` | — | Remove órfãs, corrige divergências | Diário 3h |

## Novos syncs a construir

| Sync novo | Fonte Oracle (validar na Fase 0) | Estratégia | Conteúdo |
|---|---|---|---|
| `Sankhya::ProductSync` | TGFPRO + TGFGRU (grupos/categorias) + unidades | Upsert por CODPROD | Descrição, categoria, unidade, ativo, marca |
| `Sankhya::OrderSync` | TGFCAB (TOP 1001 e demais TOPs de pedido) **com histórico** | Upsert por NUNOTA (evolução do snapshot atual) | Cabeçalho do pedido com situação (pendente/faturado/cancelado/bloqueado) |
| `Sankhya::ItemSync` | TGFITE (itens de pedidos e notas) | Upsert por (NUNOTA, SEQUENCIA) | Produto, quantidade, preço, desconto, custo, total |
| `Sankhya::CostSync` | TGFCUS / custo gerencial do produto | Upsert diário | Custo vigente por produto (base do cálculo de margem) |
| `Sankhya::StockSync` | TGFEST | Snapshot | Estoque disponível/reservado por produto e empresa |
| `Sankhya::PriceSync` | TGFTAB/TGFEXC (tabelas de preço) | Upsert / consulta em tempo real | Preço vigente e tabela aplicável |
| `Sankhya::CreditSync` | TGFPAR (limite de crédito) + TGFFIN (em aberto) | Snapshot | Limite, saldo devedor, bloqueio, inadimplência por parceiro |
| Enriquecimento de `partners` | TGFPAR (CNPJ, cidade, UF, segmento/ramo, situação) | Upsert | Campos novos no espelho de parceiros |

## Frequências de sincronização (alvo, seção 4.3 do PDF)

Configurar em `config/recurring.yml` (Solid Queue recurring):

| Informação | Frequência inicial |
|---|---|
| Pedidos | A cada 10 minutos |
| Faturamento e notas | A cada 15 minutos |
| Cancelamentos e devoluções | A cada 15 minutos |
| Estoque | A cada 30 minutos |
| Crédito e financeiro | A cada 30 minutos |
| Clientes, produtos e preços | A cada 2 horas |
| Custos | Diariamente |
| Reconciliação completa | Rotina noturna (manter 3h) |

> Nota: o cron atual roda apenas 8h–19h em dias úteis. Manter essa janela para os syncs frequentes e usar a madrugada para custos, reconcile e previsões em lote.

## Consultas em tempo real (seção 4.4)

Quando o dado precisar estar rigorosamente atualizado — especialmente antes de uma recomendação sensível — a aplicação consulta o Sankhya na hora, via `Sankhya::Client` (com cache curto de 1–5 min):

- Estoque e disponibilidade comercial;
- Preço vigente e tabela aplicável;
- Limite de crédito e inadimplência;
- Situação atual do pedido;
- Bloqueios, restrições e ocorrências críticas.

Implementar como `Sankhya::LiveQueries` (métodos pontuais, um SELECT cada, com timeout curto e fallback para o espelho local + carimbo de "dado de {timestamp}").

## Carga inicial (backfill)

A base analítica deve começar com **24 meses de histórico** — período que captura frequência, sazonalidade, tendências, crescimento, redução de consumo e padrões de recompra:

- Clientes e vendedores;
- Produtos, categorias e unidades;
- Pedidos, itens e situações;
- Notas fiscais e faturamento;
- Cancelamentos e devoluções;
- Custos e margens;
- Estoques e tabelas de preços;
- Financeiro, crédito e bloqueios.

Operacionalização: estender `lib/tasks/sankhya.rake` com tasks de backfill por entidade (`sankhya:backfill_products`, `sankhya:backfill_items`, etc.), com paginação keyset e execução em lotes fora do horário comercial. O backfill atual de invoices serve de modelo.

## Fase 0 — Diagnóstico técnico (pré-requisito)

Antes de codificar os novos syncs, validar no Sankhya da Jatto (com o responsável Sankhya):

1. Tabelas e campos reais de produtos, itens, estoque, custos e preços (TGFPRO, TGFITE, TGFEST, TGFCUS, TGFTAB — nomes a confirmar, podem ter customizações).
2. TOPs efetivamente usados para pedido, venda, devolução e cancelamento (hoje: 1001, 1101, 1201/1202).
3. Como o crédito/bloqueio do parceiro é representado.
4. Volumetria de 24 meses de TGFITE (dimensionar backfill e índices).
5. Limites de rate/timeout do Gateway para as novas frequências (10 min).
6. Permissões do usuário de integração para as novas tabelas.

Registrar o resultado em `docs/forca-de-vendas-360/fase-0-diagnostico.md` (criar durante a execução).

## Alertas de integração (ver doc 09)

- Sincronização atrasada (sem `sync_run` de sucesso além do intervalo esperado);
- Token inválido ou timeout recorrente;
- Registros pendentes ou duplicados;
- Divergência entre faturamento do ERP e base analítica (conciliação).
