<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import FilterBar from '@/components/FilterBar.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import { brl, brlCompact, num, monthLabel } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'
import type {
  Summary,
  DelinquencySummary,
  PortfolioSummary,
  MonthlyRow,
  RankingRow,
  AppliedFilters,
  FilterOptions,
} from '@/types/models'

defineOptions({ layout: AppLayout })

const props = defineProps<{
  summary: Summary
  delinquency: DelinquencySummary
  portfolio: PortfolioSummary
  monthly: MonthlyRow[]
  topSalespeople: RankingRow[]
  topPartners: RankingRow[]
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const monthlyOption = computed(() => ({
  color: [PALETTE[0]],
  grid: GRID,
  tooltip: {
    trigger: 'axis',
    formatter: (params: any) => {
      const row = props.monthly[params[0].dataIndex]
      return `<b>${monthLabel(row.month)}</b><br/>Líquido: ${brl(row.net)}<br/>Bruto: ${brl(row.sales)}<br/>Devoluções: ${brl(row.returns)}<br/>Notas: ${num(row.count)}`
    },
  },
  xAxis: { type: 'category', data: props.monthly.map((r) => monthLabel(r.month)) },
  yAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
  series: [{ type: 'bar', data: props.monthly.map((r) => r.net), barMaxWidth: 48, itemStyle: { borderRadius: [4, 4, 0, 0] } }],
}))

const delinquencyOption = computed(() => {
  const py = props.delinquency.protested_by_year
  return {
    tooltip: { trigger: 'item', formatter: (p: any) => `${p.name}: ${brl(p.value)} (${p.percent}%)` },
    legend: { bottom: 0, icon: 'circle', textStyle: { fontSize: 11 } },
    series: [
      {
        type: 'pie',
        radius: ['45%', '70%'],
        label: { show: false },
        data: [
          { name: 'Em aberto', value: props.delinquency.open_total, itemStyle: { color: '#f59e0b' } },
          { name: 'Protest. 2026', value: py['2026'] ?? 0, itemStyle: { color: '#ef4444' } },
          { name: 'Protest. 2025', value: py['2025'] ?? 0, itemStyle: { color: '#b91c1c' } },
          { name: 'Protest. 2024', value: py['2024'] ?? 0, itemStyle: { color: '#7f1d1d' } },
        ].filter((d) => d.value > 0),
      },
    ],
  }
})

function rankingOption(rows: RankingRow[], color: string) {
  const ordered = [...rows].sort((a, b) => a.net - b.net)
  return {
    grid: { ...GRID, left: 8 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: (p: any) => `<b>${p[0].name}</b><br/>Líquido: ${brl(p[0].value)}` },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: ordered.map((r) => r.name) },
    series: [{ type: 'bar', data: ordered.map((r) => r.net), itemStyle: { color, borderRadius: [0, 4, 4, 0] }, barMaxWidth: 20 }],
  }
}

const salespeopleOption = computed(() => rankingOption(props.topSalespeople, PALETTE[0]))
const partnersOption = computed(() => rankingOption(props.topPartners, PALETTE[2]))
</script>

<template>
  <Head title="Visão geral" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Visão geral</h1>
      <p class="text-sm text-slate-500">Faturamento, carteira e inadimplência consolidados</p>
    </div>

    <FilterBar :filters="filters" :options="filterOptions" />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <KpiCard
        label="Faturamento líquido"
        :value="brl(summary.net_revenue)"
        tone="positive"
        hint="Vendas menos devoluções no recorte selecionado (apenas notas confirmadas)."
        hint-scope="all"
      />
      <KpiCard
        label="Faturamento bruto"
        :value="brl(summary.gross_sales)"
        :sub="`${num(summary.invoice_count)} notas`"
        hint="Soma das vendas (notas confirmadas) no recorte, sem descontar devoluções."
        hint-scope="all"
      />
      <KpiCard
        label="Devoluções"
        :value="brl(summary.returns_total)"
        :tone="summary.returns_total > 0 ? 'negative' : 'default'"
        hint="Total das notas de devolução no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Carteira a faturar"
        :value="brl(portfolio.total)"
        :sub="`${num(portfolio.count)} pedidos`"
        hint="Pedidos liberados e ainda não faturados. É o total atual da carteira inteira — não muda com os filtros deste painel."
        hint-scope="none"
        hint-note="Total atual — ignora os filtros"
      />
      <KpiCard
        label="Inadimplência (aberto)"
        :value="brl(delinquency.open_total)"
        tone="warning"
        hint="Títulos em aberto do último sincronismo. Valor global — não é recortado pelos filtros."
        hint-scope="none"
        hint-note="Snapshot — ignora os filtros"
      />
      <KpiCard
        label="Saldo devedor"
        :value="brl(delinquency.saldo_devedor)"
        :sub="`c/ protestado ${brl(delinquency.protested_total)}`"
        tone="negative"
        hint="Em aberto + protestado (snapshot do ERP). Valor global — não é afetado pelos filtros."
        hint-scope="none"
        hint-note="Snapshot — ignora os filtros"
      />
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div class="lg:col-span-2">
        <ChartCard
          title="Faturamento mês a mês"
          subtitle="Valor líquido (vendas − devoluções)"
          hint="Faturamento líquido consolidado por mês, no recorte selecionado."
          hint-scope="all"
        >
          <BaseChart :option="monthlyOption" :height="320" />
        </ChartCard>
      </div>
      <ChartCard
        title="Inadimplência"
        subtitle="Aberto vs protestado por ano"
        hint="Distribuição do valor inadimplente entre em aberto e protestado por ano. Snapshot do ERP."
        hint-scope="none"
        hint-note="Snapshot — ignora os filtros"
      >
        <BaseChart :option="delinquencyOption" :height="320" />
      </ChartCard>
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <ChartCard
        title="Top vendedores"
        subtitle="Por faturamento líquido"
        hint="Vendedores com maior faturamento líquido no recorte selecionado."
        hint-scope="all"
      >
        <BaseChart :option="salespeopleOption" :height="360" />
      </ChartCard>
      <ChartCard
        title="Top parceiros"
        subtitle="Por faturamento líquido"
        hint="Parceiros com maior faturamento líquido no recorte selecionado."
        hint-scope="all"
      >
        <BaseChart :option="partnersOption" :height="360" />
      </ChartCard>
    </div>
  </div>
</template>
