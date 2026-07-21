<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import { num, dateBR } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'

defineOptions({ layout: AppLayout })

interface Summary {
  month_cost: number
  monthly_budget: number
  month_ratio: number | null
  today_cost: number
  today_tokens: number
  daily_token_budget: number
  per_seller_daily_cap: number
  warning_ratio: number
  total_runs: number
  error_runs: number
  agent_enabled: boolean
}
interface DayRow { day: string; calls: number; cost: number; tokens: number; errors: number }
interface UserRow { user: string; calls: number; cost: number; tokens: number; last_at: string | null }
interface SellerRow { salesperson: string; calls: number; cost: number; tokens: number; today_cost: number; daily_cap: number }
interface ToolRow { name: string; calls: number; avg_ms: number; failures: number }
interface RunRow {
  id: number; at: string; kind: string; status: string; model: string | null
  user: string | null; salesperson: string | null; cost: number; tokens: number
  cache_read: number; latency_ms: number | null; tools: string[]
}
interface SyncRow { at: string; status: string; kind: string | null; errors: number }
interface AlertRow { id: number; area: string; area_label: string; severity: 'low' | 'medium' | 'high'; title: string; message: string | null; at: string }

interface ExportRow { id: number; kind: string; format: string; row_count: number; user: string | null; at: string }

const props = defineProps<{
  summary: Summary
  byDay: DayRow[]
  byUser: UserRow[]
  bySeller: SellerRow[]
  topTools: ToolRow[]
  recentRuns: RunRow[]
  syncRuns: SyncRow[]
  exports: ExportRow[]
  alerts: { by_area: { area: string; label: string; count: number }[]; recent: AlertRow[] }
}>()

// US$ com até 4 casas (custos individuais são centavos de centavo).
function usd(value: number | null | undefined): string {
  return `US$ ${(value ?? 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 4 })}`
}

const KIND_LABELS: Record<string, string> = {
  copilot: 'Copiloto', daily_plan: 'Plano do dia', simulation: 'Simulação', batch: 'Lote', cockpit_summary: 'Resumo cockpit',
}
const STATUS_LABELS: Record<string, string> = {
  ok: 'OK', error: 'Erro', refused: 'Recusado', invalid_schema: 'Schema inválido',
}
function statusCls(status: string): string {
  return status === 'ok'
    ? 'bg-emerald-50 text-emerald-700 ring-emerald-600/20'
    : 'bg-red-50 text-red-700 ring-red-600/20'
}
const SEVERITY: Record<AlertRow['severity'], string> = {
  high: 'bg-red-50 text-red-700 ring-red-600/20',
  medium: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  low: 'bg-slate-100 text-slate-600 ring-slate-400/20',
}

// Tom do card de custo mensal: alerta ao cruzar a fração de aviso do teto.
const monthTone = computed(() => {
  const r = props.summary.month_ratio
  if (r == null) return 'default'
  if (r >= 100) return 'negative'
  return r >= props.summary.warning_ratio * 100 ? 'warning' : 'positive'
})

const costChart = computed(() => ({
  color: [PALETTE[1], PALETTE[3]],
  grid: { ...GRID, left: 8 },
  legend: { top: 0, icon: 'circle', textStyle: { fontSize: 11 } },
  tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } },
  xAxis: { type: 'category', data: props.byDay.map((d) => d.day.slice(5)) },
  yAxis: [
    { type: 'value', name: 'US$', axisLabel: { formatter: (v: number) => `$${v.toFixed(2)}` } },
    { type: 'value', name: 'tokens', axisLabel: { formatter: (v: number) => num(v) } },
  ],
  series: [
    { name: 'Custo (US$)', type: 'bar', data: props.byDay.map((d) => d.cost), barMaxWidth: 18, itemStyle: { borderRadius: [3, 3, 0, 0] } },
    { name: 'Tokens', type: 'line', yAxisIndex: 1, smooth: true, data: props.byDay.map((d) => d.tokens) },
  ],
}))
</script>

<template>
  <Head title="Auditoria" />

  <div class="space-y-6">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold text-slate-800">Auditoria</h1>
        <p class="text-sm text-slate-500">Gasto do agente Claude (por dia, usuário e vendedor), sincronizações e alertas.</p>
      </div>
      <div class="flex items-center gap-3">
        <span
          v-if="!summary.agent_enabled"
          class="inline-flex items-center rounded-full bg-amber-50 px-3 py-1 text-xs font-medium text-amber-700 ring-1 ring-amber-600/20"
        >
          Agente desabilitado (sem ANTHROPIC_API_KEY)
        </span>
        <a
          href="/auditoria/exportar"
          class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-600 shadow-sm transition hover:bg-slate-50"
        >
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="h-4 w-4">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" />
          </svg>
          Exportar CSV
        </a>
      </div>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <KpiCard
        label="Custo do mês"
        :value="usd(summary.month_cost)"
        :tone="monthTone"
        :sub="`de ${usd(summary.monthly_budget)}${summary.month_ratio != null ? ` · ${summary.month_ratio}%` : ''}`"
        hint="Custo estimado acumulado do mês (copiloto + resumo + abordagens) contra o teto global AGENT_MONTHLY_COST_BUDGET_USD."
      />
      <KpiCard
        label="Custo hoje"
        :value="usd(summary.today_cost)"
        :sub="`teto/vendedor: ${usd(summary.per_seller_daily_cap)}/dia`"
        hint="Custo estimado de hoje (dia de negócio, fuso BR)."
      />
      <KpiCard
        label="Tokens hoje"
        :value="num(summary.today_tokens)"
        :sub="`backstop: ${num(summary.daily_token_budget)}`"
        hint="Tokens de hoje (input + output + cache write) contra o backstop absoluto AGENT_DAILY_TOKEN_BUDGET."
      />
      <KpiCard
        label="Execuções"
        :value="num(summary.total_runs)"
        :tone="summary.error_runs > 0 ? 'warning' : 'default'"
        :sub="`${summary.error_runs} com erro/recusa`"
        hint="Total de execuções do agente registradas em agent_runs."
      />
    </div>

    <ChartCard
      v-if="byDay.length"
      title="Custo e tokens por dia"
      subtitle="Últimos 30 dias (dia de negócio, fuso BR)"
    >
      <BaseChart :option="costChart" :height="320" />
    </ChartCard>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Gasto por usuário</h3></header>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-slate-200 text-sm">
            <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-4 py-3 font-medium">Usuário</th>
                <th class="px-3 py-3 text-right font-medium">Exec.</th>
                <th class="px-3 py-3 text-right font-medium">Custo</th>
                <th class="px-3 py-3 text-right font-medium">Tokens</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="u in byUser" :key="u.user" class="bg-white hover:bg-slate-50">
                <td class="px-4 py-2.5 font-medium text-slate-700">{{ u.user }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-slate-500">{{ u.calls }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-slate-700">{{ usd(u.cost) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-slate-500">{{ num(u.tokens) }}</td>
              </tr>
              <tr v-if="byUser.length === 0"><td colspan="4" class="px-4 py-8 text-center text-slate-400">Sem execuções na janela.</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Gasto por vendedor (contexto)</h3></header>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-slate-200 text-sm">
            <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-4 py-3 font-medium">Vendedor</th>
                <th class="px-3 py-3 text-right font-medium">Exec.</th>
                <th class="px-3 py-3 text-right font-medium">Custo (30d)</th>
                <th class="px-3 py-3 text-right font-medium">Hoje / teto</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="s in bySeller" :key="s.salesperson" class="bg-white hover:bg-slate-50">
                <td class="px-4 py-2.5 font-medium text-slate-700">{{ s.salesperson }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-slate-500">{{ s.calls }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums text-slate-700">{{ usd(s.cost) }}</td>
                <td class="px-3 py-2.5 text-right tabular-nums" :class="s.today_cost >= s.daily_cap ? 'text-red-600' : 'text-slate-500'">
                  {{ usd(s.today_cost) }} / {{ usd(s.daily_cap) }}
                </td>
              </tr>
              <tr v-if="bySeller.length === 0"><td colspan="4" class="px-4 py-8 text-center text-slate-400">Sem execuções por vendedor na janela.</td></tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Ferramentas mais chamadas</h3></header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-4 py-3 font-medium">Ferramenta</th>
              <th class="px-3 py-3 text-right font-medium">Chamadas</th>
              <th class="px-3 py-3 text-right font-medium">Duração média</th>
              <th class="px-3 py-3 text-right font-medium">Falhas</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="t in topTools" :key="t.name" class="bg-white hover:bg-slate-50">
              <td class="px-4 py-2.5 font-mono text-xs text-slate-700">{{ t.name }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-slate-600">{{ t.calls }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-slate-500">{{ t.avg_ms }} ms</td>
              <td class="px-3 py-2.5 text-right tabular-nums" :class="t.failures > 0 ? 'text-red-600' : 'text-slate-300'">{{ t.failures }}</td>
            </tr>
            <tr v-if="topTools.length === 0"><td colspan="4" class="px-4 py-8 text-center text-slate-400">Nenhuma ferramenta chamada na janela.</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Execuções recentes</h3></header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-4 py-3 font-medium">Quando</th>
              <th class="px-3 py-3 font-medium">Tipo</th>
              <th class="px-3 py-3 font-medium">Usuário / vendedor</th>
              <th class="px-3 py-3 font-medium">Modelo</th>
              <th class="px-3 py-3 text-right font-medium">Custo</th>
              <th class="px-3 py-3 text-right font-medium">Tokens</th>
              <th class="px-3 py-3 text-center font-medium">Status</th>
              <th class="px-3 py-3 font-medium">Ferramentas</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="r in recentRuns" :key="r.id" class="bg-white align-top hover:bg-slate-50">
              <td class="whitespace-nowrap px-4 py-2.5 text-xs text-slate-500">{{ dateBR(r.at) }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-slate-600">{{ KIND_LABELS[r.kind] ?? r.kind }}</td>
              <td class="px-3 py-2.5 text-xs text-slate-600">
                {{ r.user ?? '—' }}<span v-if="r.salesperson" class="text-slate-400"> · {{ r.salesperson }}</span>
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-xs text-slate-500">{{ r.model ?? '—' }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums text-slate-700">{{ usd(r.cost) }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums text-slate-500">{{ num(r.tokens) }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-center">
                <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset" :class="statusCls(r.status)">
                  {{ STATUS_LABELS[r.status] ?? r.status }}
                </span>
              </td>
              <td class="px-3 py-2.5 text-xs text-slate-500">{{ r.tools.length ? r.tools.join(', ') : '—' }}</td>
            </tr>
            <tr v-if="recentRuns.length === 0"><td colspan="8" class="px-4 py-8 text-center text-slate-400">Nenhuma execução registrada.</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Sincronizações recentes</h3></header>
        <ul class="divide-y divide-slate-100">
          <li v-for="(s, i) in syncRuns" :key="i" class="flex items-center justify-between gap-3 px-5 py-3">
            <div class="min-w-0">
              <p class="text-sm font-medium" :class="s.status === 'ok' ? 'text-slate-700' : 'text-amber-700'">
                {{ s.status === 'ok' ? 'Concluído' : s.status }}<span v-if="s.kind" class="text-slate-400"> · {{ s.kind }}</span>
              </p>
              <p v-if="s.errors > 0" class="text-xs text-red-500">{{ s.errors }} erro(s)</p>
            </div>
            <span class="whitespace-nowrap text-xs text-slate-400">{{ dateBR(s.at) }}</span>
          </li>
          <li v-if="syncRuns.length === 0" class="px-5 py-8 text-center text-slate-400">Nenhum sync registrado.</li>
        </ul>
      </section>

      <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <header class="flex items-center justify-between border-b border-slate-200 px-5 py-3">
          <h3 class="text-sm font-semibold text-slate-700">Alertas abertos</h3>
          <div class="flex flex-wrap gap-1.5">
            <span v-for="a in alerts.by_area" :key="a.area" class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-600">
              {{ a.label }} <span class="font-semibold">{{ a.count }}</span>
            </span>
          </div>
        </header>
        <ul class="divide-y divide-slate-100">
          <li v-for="a in alerts.recent" :key="a.id" class="flex items-start gap-3 px-5 py-3">
            <span class="mt-0.5 inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset" :class="SEVERITY[a.severity]">
              {{ a.area_label }}
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-slate-700">{{ a.title }}</p>
              <p v-if="a.message" class="truncate text-xs text-slate-500">{{ a.message }}</p>
            </div>
            <span class="whitespace-nowrap text-xs text-slate-400">{{ dateBR(a.at) }}</span>
          </li>
          <li v-if="alerts.recent.length === 0" class="px-5 py-8 text-center text-slate-400">Nenhum alerta aberto.</li>
        </ul>
      </section>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3"><h3 class="text-sm font-semibold text-slate-700">Exportações registradas</h3></header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-4 py-3 font-medium">Quando</th>
              <th class="px-3 py-3 font-medium">Tipo</th>
              <th class="px-3 py-3 font-medium">Formato</th>
              <th class="px-3 py-3 text-right font-medium">Linhas</th>
              <th class="px-3 py-3 font-medium">Usuário</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="e in exports" :key="e.id" class="bg-white hover:bg-slate-50">
              <td class="whitespace-nowrap px-4 py-2.5 text-xs text-slate-500">{{ dateBR(e.at) }}</td>
              <td class="px-3 py-2.5 text-slate-700">{{ e.kind }}</td>
              <td class="px-3 py-2.5 uppercase text-xs text-slate-500">{{ e.format }}</td>
              <td class="px-3 py-2.5 text-right tabular-nums text-slate-500">{{ e.row_count }}</td>
              <td class="px-3 py-2.5 text-xs text-slate-600">{{ e.user ?? '—' }}</td>
            </tr>
            <tr v-if="exports.length === 0"><td colspan="5" class="px-4 py-8 text-center text-slate-400">Nenhuma exportação registrada ainda.</td></tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
