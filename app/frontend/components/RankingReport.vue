<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link } from '@inertiajs/vue3'
import FilterBar from '@/components/FilterBar.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import InfoHint from '@/components/InfoHint.vue'
import { brl, brlCompact, num, monthLabel } from '@/lib/format'
import { matchesQuery } from '@/lib/search'
import { PALETTE, GRID } from '@/lib/charts'
import type { Summary, RankingRow, Evolution, AppliedFilters, FilterOptions } from '@/types/models'

const props = defineProps<{
  entity: string
  summary: Summary
  ranking: RankingRow[]
  evolution: Evolution
  filters: AppliedFilters
  filterOptions: FilterOptions
  // Quando true, o nome linka para o Cliente 360 (só faz sentido em Parceiros).
  clientLink?: boolean
}>()

const maxNet = computed(() => Math.max(1, ...props.ranking.map((r) => r.net)))

// Filtro instantâneo da tabela de detalhamento (não mexe nos gráficos/KPIs).
const query = ref('')
const filteredRanking = computed(() => props.ranking.filter((r) => matchesQuery(r.name, query.value)))

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
      <KpiCard
        label="Faturamento líquido"
        :value="brl(summary.net_revenue)"
        tone="positive"
        hint="Vendas menos devoluções no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Faturamento bruto"
        :value="brl(summary.gross_sales)"
        hint="Soma das vendas (notas confirmadas) no recorte, sem descontar devoluções."
        hint-scope="all"
      />
      <KpiCard
        label="Notas"
        :value="num(summary.invoice_count)"
        hint="Número de notas de venda no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Ticket médio"
        :value="brl(summary.avg_ticket)"
        hint="Faturamento bruto dividido pelo número de notas, no recorte."
        hint-scope="all"
      />
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <ChartCard
        title="Evolução mês a mês"
        :subtitle="`Líquido por ${entity.toLowerCase()} (top 8)`"
        :hint="`Evolução mensal do faturamento líquido dos maiores ${entity.toLowerCase()}s, no recorte selecionado.`"
        hint-scope="all"
      >
        <BaseChart :option="evolutionOption" :height="360" />
      </ChartCard>
      <ChartCard
        title="Ranking"
        :subtitle="`Top 12 ${entity.toLowerCase()}s por líquido`"
        :hint="`Maiores ${entity.toLowerCase()}s por faturamento líquido no recorte selecionado.`"
        hint-scope="all"
      >
        <BaseChart :option="rankingBarOption" :height="360" />
      </ChartCard>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-3">
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          Detalhamento por {{ entity.toLowerCase() }}
          <InfoHint
            :text="`Uma linha por ${entity.toLowerCase()} com notas, bruto, devoluções, comissão e líquido, no recorte selecionado.`"
            scope="all"
          />
        </h3>
        <div class="relative">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"
               class="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400">
            <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-4.35-4.35m1.85-5.15a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z" />
          </svg>
          <input
            v-model="query"
            type="search"
            :placeholder="`Buscar ${entity.toLowerCase()}…`"
            :aria-label="`Buscar ${entity.toLowerCase()} na lista`"
            class="w-56 rounded-lg border border-slate-200 bg-white py-1.5 pl-8 pr-3 text-sm text-slate-700 placeholder:text-slate-400 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-400"
          />
        </div>
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
            <tr v-for="row in filteredRanking" :key="row.id" class="hover:bg-slate-50">
              <td class="px-5 py-3 font-medium text-slate-700">
                <Link v-if="clientLink" :href="`/clientes/${row.id}`" class="text-indigo-600 hover:underline">{{ row.name }}</Link>
                <span v-else>{{ row.name }}</span>
              </td>
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
            <tr v-if="filteredRanking.length === 0">
              <td colspan="6" class="px-5 py-10 text-center text-slate-400">
                {{ ranking.length === 0 ? 'Nenhum dado no período selecionado.' : `Nenhum ${entity.toLowerCase()} encontrado para “${query}”.` }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
