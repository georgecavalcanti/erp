<script setup lang="ts">
import { computed, ref } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import KpiCard from '@/components/KpiCard.vue'
import { brl, percent, dateBR } from '@/lib/format'
import { matchesQuery } from '@/lib/search'

defineOptions({ layout: AppLayout })

// Status do desvio (projeção provável vs. meta) → rótulo + cor do badge.
type Status = 'no_alvo' | 'atencao' | 'critico' | 'sem_meta'
interface TeamRow {
  salesperson_id: number
  name: string
  target: number | null
  realized: number
  realized_margin: number
  expected_to_date: number | null
  attainment_percent: number | null
  projected_likely: number | null
  projected_low: number | null
  projected_high: number | null
  confidence: number | null
  gap: number | null
  behind_pace: boolean
  status: Status
}
interface Totals {
  count: number
  target: number
  realized: number
  realized_margin: number
  projected_likely: number
  gap: number
  attainment_percent: number | null
  at_risk_count: number
  behind_pace_count: number
}
interface AlertRow {
  id: number
  area: string
  area_label: string
  severity: 'low' | 'medium' | 'high'
  title: string
  message: string | null
  at: string
}

const props = defineProps<{
  month: string
  rows: TeamRow[]
  totals: Totals
  alerts: AlertRow[]
  readonly: boolean
}>()

const query = ref('')
const filteredRows = computed(() => props.rows.filter((r) => matchesQuery(r.name, query.value)))

const STATUS: Record<Status, { label: string; cls: string }> = {
  no_alvo: { label: 'No alvo', cls: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20' },
  atencao: { label: 'Atenção', cls: 'bg-amber-50 text-amber-700 ring-amber-600/20' },
  critico: { label: 'Crítico', cls: 'bg-red-50 text-red-700 ring-red-600/20' },
  sem_meta: { label: 'Sem meta', cls: 'bg-slate-100 text-slate-500 ring-slate-400/20' },
}
const SEVERITY: Record<AlertRow['severity'], string> = {
  high: 'bg-red-50 text-red-700 ring-red-600/20',
  medium: 'bg-amber-50 text-amber-700 ring-amber-600/20',
  low: 'bg-slate-100 text-slate-600 ring-slate-400/20',
}

// Banda conservador–potencial (só quando há projeção persistida).
function band(row: TeamRow): string {
  if (row.projected_low == null || row.projected_high == null) return '—'
  return `${brl(row.projected_low)} – ${brl(row.projected_high)}`
}
</script>

<template>
  <Head title="Dashboard do gestor" />

  <div class="space-y-6">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold text-slate-800">Dashboard do gestor</h1>
        <p class="text-sm text-slate-500">
          Equipe: meta, realizado e projeção do mês ({{ month }}), com desvios e alertas.
        </p>
      </div>
      <span
        v-if="readonly"
        class="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-500 ring-1 ring-slate-400/20"
      >
        Somente leitura (diretoria)
      </span>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <KpiCard
        label="Realizado (líquido)"
        :value="brl(totals.realized)"
        tone="positive"
        :sub="`${totals.count} vendedor(es) no escopo`"
        hint="Vendas menos devoluções da equipe no mês corrente."
      />
      <KpiCard
        label="Meta da equipe"
        :value="brl(totals.target)"
        :sub="totals.attainment_percent != null ? `${percent(totals.attainment_percent)} atingido` : 'sem metas'"
        hint="Soma das metas de faturamento (kind revenue) dos vendedores no escopo, no mês."
      />
      <KpiCard
        label="Projeção provável"
        :value="brl(totals.projected_likely)"
        :tone="totals.projected_likely >= totals.target && totals.target > 0 ? 'positive' : 'warning'"
        hint="Soma do cenário provável da última projeção persistida de cada vendedor."
      />
      <KpiCard
        label="Vendedores em risco"
        :value="String(totals.at_risk_count)"
        :tone="totals.at_risk_count > 0 ? 'negative' : 'default'"
        :sub="`${totals.behind_pace_count} atrasado(s) no ritmo`"
        hint="Projeção provável abaixo da meta (atenção até −15%, crítico abaixo disso)."
      />
    </div>

    <section
      v-if="alerts.length"
      class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm"
    >
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="text-sm font-semibold text-slate-700">Alertas abertos da equipe</h3>
      </header>
      <ul class="divide-y divide-slate-100">
        <li v-for="a in alerts" :key="a.id" class="flex items-start gap-3 px-5 py-3">
          <span class="mt-0.5 inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset" :class="SEVERITY[a.severity]">
            {{ a.area_label }}
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-medium text-slate-700">{{ a.title }}</p>
            <p v-if="a.message" class="truncate text-xs text-slate-500">{{ a.message }}</p>
          </div>
          <span class="whitespace-nowrap text-xs text-slate-400">{{ dateBR(a.at) }}</span>
        </li>
      </ul>
    </section>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-3">
        <h3 class="text-sm font-semibold text-slate-700">Equipe por vendedor</h3>
        <div class="relative">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"
               class="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400">
            <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-4.35-4.35m1.85-5.15a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z" />
          </svg>
          <input
            v-model="query"
            type="search"
            placeholder="Buscar vendedor…"
            aria-label="Buscar vendedor na lista"
            class="w-56 rounded-lg border border-slate-200 bg-white py-1.5 pl-8 pr-3 text-sm text-slate-700 placeholder:text-slate-400 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-400"
          />
        </div>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="sticky left-0 z-10 bg-slate-50 px-4 py-3 font-medium">Vendedor</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Meta</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Realizado</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Atingido</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Esperado hoje</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Proj. provável</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Banda (cons.–pot.)</th>
              <th class="whitespace-nowrap px-3 py-3 text-right font-medium">Gap</th>
              <th class="whitespace-nowrap px-3 py-3 text-center font-medium">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="row in filteredRows" :key="row.salesperson_id" class="bg-white hover:bg-slate-50">
              <td class="sticky left-0 z-10 border-r border-slate-100 bg-inherit px-4 py-2.5 font-medium text-slate-700">
                {{ row.name }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums" :class="row.target ? 'text-slate-600' : 'text-slate-300'">
                {{ row.target != null ? brl(row.target) : '—' }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums text-slate-700">{{ brl(row.realized) }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums" :class="row.attainment_percent == null ? 'text-slate-300' : row.attainment_percent >= 100 ? 'text-emerald-600' : 'text-slate-600'">
                {{ row.attainment_percent != null ? percent(row.attainment_percent) : '—' }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums" :class="row.behind_pace ? 'text-amber-600' : 'text-slate-400'">
                {{ row.expected_to_date != null ? brl(row.expected_to_date) : '—' }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums" :class="row.projected_likely != null ? 'text-slate-600' : 'text-slate-300'">
                {{ row.projected_likely != null ? brl(row.projected_likely) : '—' }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right text-xs tabular-nums text-slate-400">{{ band(row) }}</td>
              <td class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums" :class="row.gap == null ? 'text-slate-300' : row.gap > 0 ? 'text-red-600' : 'text-emerald-600'">
                {{ row.gap != null ? brl(row.gap) : '—' }}
              </td>
              <td class="whitespace-nowrap px-3 py-2.5 text-center">
                <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset" :class="STATUS[row.status].cls">
                  {{ STATUS[row.status].label }}
                </span>
              </td>
            </tr>
            <tr v-if="filteredRows.length === 0">
              <td colspan="9" class="px-4 py-10 text-center text-slate-400">
                {{ rows.length === 0 ? 'Nenhum vendedor no escopo com meta ou faturamento no mês.' : `Nenhum vendedor encontrado para “${query}”.` }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
