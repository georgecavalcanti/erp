# Runbook — Sync Sankhya (cron, reconcile, cutover)

Como os 4 datasets do painel se mantêm em dia a partir da API do Sankhya, e o que
fazer/não fazer no agendamento. Fonte da verdade é o ERP; o Postgres é um espelho.

## Estratégias por dataset

| Dataset | Model | Estratégia | Deleção no ERP se reflete? |
|---|---|---|---|
| Notas (fat.+devol.) | `Invoice` | **upsert por NUNOTA** (nunca apaga) | ❌ só via `invoices_reconcile` |
| Carteira | `PendingOrder` | **snapshot** (`delete_all`+recria, em transação) | ✅ auto-cura a cada run |
| Inadimplência | `OverdueTitle`+`Delinquency` | **snapshot** (recria + re-deriva) | ✅ auto-cura a cada run |

Os snapshots são atômicos (transação): se a API falhar no meio, o conjunto anterior
fica intacto — nunca esvazia a tela.

O ponto cego é o `Invoice`: o incremental (`DTALTER`) só vê nota **alterada**, nunca
**deletada/estornada** que saiu de escopo. Sem reconcile, ela vira órfã e infla o
faturamento. Ver `Invoice.confirmed_only` (conta só `STATUSNOTA='L'`) + reconcile abaixo.

## Cron recomendado (Railway)

| Job | Cadência | Comando |
|---|---|---|
| Sync frequente | a cada 30–60 min, 8h–19h | `bin/rails sankhya:sync` |
| Reconcile de notas | 1×/dia (madrugada) | `bin/rails "sankhya:invoices_reconcile[90]"` |
| Backfill full (opcional) | 1×/semana | `bin/rails sankhya:invoices_all` |

`sankhya:sync` é **resiliente** (uma falha de dataset não derruba os outros dois) e usa
**advisory lock** — se um run demora e o próximo dispara, o segundo pula em vez de
rodar sobreposto (evitaria deadlock no `delete_all`+insert dos snapshots).

## Reconcile — o que faz e as travas

`sankhya:invoices_reconcile[dias]` (default 90):
1. Faz **upsert** de todas as notas da janela (refresca edições que o incremental perdeu).
2. **Apaga** as notas locais da janela cujo NUNOTA **não voltou** da API (deletadas/estornadas).
3. Preserva `paid`/`paid_at` das sobreviventes (só remove as ausentes).

Travas de segurança:
- Falha de página propaga `Sankhya::Error` → cai no rescue **antes** de qualquer delete.
- Janela vazia (`seen` vazio) → **aborta sem apagar** (não zera o período por falha silenciosa).
- Sempre dá pra inspecionar antes: `sankhya:invoices_reconcile_dry[90]` lista as órfãs
  (e marca `PAGO` nas que perderiam a marcação manual) sem apagar nada.

## ⛔ `bootstrap` — nunca no cron

`sankhya:bootstrap` dá `TRUNCATE` nos fatos+dimensões e repopula do zero. É **cutover
único e manual**, travado por `CONFIRM_PROD_WIPE=faturamento`. Por que não agendar:
- **Apaga `paid`/`paid_at`** — marcação manual de pagamento (o writer blinda isso de propósito).
- O `TRUNCATE` não está na mesma transação do repopulate: se a API falhar no meio, as
  tabelas ficam **vazias** até a próxima rodada boa.

Para "refrescar tudo" sem esses riscos, use `invoices_reconcile` (janela grande) — upsert,
não-destrutivo, preserva `paid`.
