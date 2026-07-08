<script setup lang="ts">
import { computed } from 'vue'
import FilterBar from '@/components/FilterBar.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import { brl, brlCompact, num, monthLabel } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'
import type { Summary, RankingRow, Evolution, AppliedFilters, FilterOptions } from '@/types/models'

const props = defineProps<{
  entity: string
  summary: Summary
  ranking: RankingRow[]
  evolution: Evolution
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const maxNet = computed(() => Math.max(1, ...props.ranking.map((r) => r.net)))

const evolutionOption = computed(() => ({
  color: PALETTE,
  grid: { ...GRID, bottom: 24 },
  tooltip: { trigger: 'axis', valueFormatter: (v: number) => brl(v) },
  legend: { type: 'scroll', bottom: 0 },
  xAxis: { type: 'category', data: props.evolution.months.map(monthLabel) },
  yAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
  series: props.evolution.series.map((s) => ({
    name: s.name,
    type: 'line',
    smooth: true,
    symbolSize: 6,
    data: s.data,
    emphasis: { focus: 'series' },
  })),
}))

const rankingBarOption = computed(() => {
  const rows = [...props.ranking].slice(0, 12).sort((a, b) => a.net - b.net)
  return {
    grid: { ...GRID, left: 8 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      formatter: (p: any) => `<b>${p[0].name}</b><br/>Líquido: ${brl(p[0].value)}`,
    },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: rows.map((r) => r.name) },
    series: [
      {
        type: 'bar',
        data: rows.map((r) => r.net),
        itemStyle: { color: PALETTE[0], borderRadius: [0, 4, 4, 0] },
        barMaxWidth: 22,
      },
    ],
  }
})
</script>

<template>
  <div class="space-y-6">
    <FilterBar :filters="filters" :options="filterOptions" />

    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <KpiCard label="Faturamento líquido" :value="brl(summary.net_revenue)" tone="positive" />
      <KpiCard label="Faturamento bruto" :value="brl(summary.gross_sales)" />
      <KpiCard label="Notas" :value="num(summary.invoice_count)" />
      <KpiCard label="Ticket médio" :value="brl(summary.avg_ticket)" />
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <ChartCard title="Evolução mês a mês" :subtitle="`Líquido por ${entity.toLowerCase()} (top 8)`">
        <BaseChart :option="evolutionOption" :height="360" />
      </ChartCard>
      <ChartCard title="Ranking" :subtitle="`Top 12 ${entity.toLowerCase()}s por líquido`">
        <BaseChart :option="rankingBarOption" :height="360" />
      </ChartCard>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="text-sm font-semibold text-slate-700">Detalhamento por {{ entity.toLowerCase() }}</h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-5 py-3 font-medium">{{ entity }}</th>
              <th class="px-5 py-3 text-right font-medium">Notas</th>
              <th class="px-5 py-3 text-right font-medium">Bruto</th>
              <th class="px-5 py-3 text-right font-medium">Devoluções</th>
              <th class="px-5 py-3 text-right font-medium">Comissão</th>
              <th class="px-5 py-3 text-right font-medium">Líquido</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="row in ranking" :key="row.id" class="hover:bg-slate-50">
              <td class="px-5 py-3 font-medium text-slate-700">{{ row.name }}</td>
              <td class="px-5 py-3 text-right tabular-nums text-slate-500">{{ num(row.count) }}</td>
              <td class="px-5 py-3 text-right tabular-nums text-slate-500">{{ brl(row.sales) }}</td>
              <td class="px-5 py-3 text-right tabular-nums" :class="row.returns > 0 ? 'text-red-600' : 'text-slate-400'">
                {{ brl(row.returns) }}
              </td>
              <td class="px-5 py-3 text-right tabular-nums text-slate-500">{{ brl(row.commission) }}</td>
              <td class="px-5 py-3 text-right">
                <div class="flex items-center justify-end gap-2">
                  <div class="hidden h-1.5 w-20 overflow-hidden rounded-full bg-slate-100 sm:block">
                    <div class="h-full rounded-full bg-indigo-500" :style="{ width: `${Math.max(2, (row.net / maxNet) * 100)}%` }" />
                  </div>
                  <span class="font-semibold tabular-nums text-slate-800">{{ brl(row.net) }}</span>
                </div>
              </td>
            </tr>
            <tr v-if="ranking.length === 0">
              <td colspan="6" class="px-5 py-10 text-center text-slate-400">Nenhum dado no período selecionado.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
