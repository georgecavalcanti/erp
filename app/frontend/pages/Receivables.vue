<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import FilterBar from '@/components/FilterBar.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import InfoHint from '@/components/InfoHint.vue'
import { brl, brlCompact, num, dateBR, monthLabel } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'
import type { DelinquencySummary, DelinquencyRow, NamedAmount, MonthAmount, AppliedFilters, FilterOptions } from '@/types/models'

defineOptions({ layout: AppLayout })

const props = defineProps<{
  summary: DelinquencySummary
  bySalesperson: DelinquencyRow[]
  byPartner: NamedAmount[]
  byDueMonth: MonthAmount[]
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const salespeopleOption = computed(() => {
  const top = [...props.bySalesperson].filter((r) => r.open > 0 || r.protested > 0).slice(0, 15).sort((a, b) => a.saldo - b.saldo)
  return {
    color: ['#f59e0b', '#ef4444'],
    grid: { ...GRID, left: 8 },
    legend: { top: 0, icon: 'circle', textStyle: { fontSize: 11 } },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, valueFormatter: (v: number) => brl(v) },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: top.map((r) => r.name) },
    series: [
      { name: 'Em aberto', type: 'bar', stack: 'x', data: top.map((r) => r.open), itemStyle: { borderRadius: [0, 0, 0, 0] }, barMaxWidth: 18 },
      { name: 'Protestado', type: 'bar', stack: 'x', data: top.map((r) => r.protested), barMaxWidth: 18 },
    ],
  }
})

const dueMonthOption = computed(() => ({
  color: [PALETTE[4]],
  grid: GRID,
  tooltip: { trigger: 'axis', valueFormatter: (v: number) => brl(v) },
  xAxis: { type: 'category', data: props.byDueMonth.map((r) => monthLabel(r.month)) },
  yAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
  series: [{ type: 'bar', data: props.byDueMonth.map((r) => r.amount), barMaxWidth: 40, itemStyle: { borderRadius: [4, 4, 0, 0] } }],
}))
</script>

<template>
  <Head title="Inadimplência" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Inadimplência</h1>
      <p class="text-sm text-slate-500">
        Situação de recebíveis por vendedor.
        <span v-if="summary.reference_date" class="text-slate-400">· até {{ dateBR(summary.reference_date) }}</span>
      </p>
    </div>

    <!-- Snapshot dos títulos em aberto: recorta por vendedor e parceiro. Data e empresa
         não se aplicam (não há data histórica nem coluna de empresa no título). -->
    <FilterBar :filters="filters" :options="filterOptions" :show-period="false" :show-company="false" />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <KpiCard
        label="Em aberto"
        :value="brl(summary.open_total)"
        tone="warning"
        hint="Total de títulos vencidos e não pagos, no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Protestado"
        :value="brl(summary.protested_total)"
        tone="negative"
        :sub="`24: ${brl(summary.protested_by_year['2024'] ?? 0)} · 25: ${brl(summary.protested_by_year['2025'] ?? 0)} · 26: ${brl(summary.protested_by_year['2026'] ?? 0)}`"
        hint="Total protestado, com a quebra por ano no subtítulo."
        hint-scope="all"
      />
      <KpiCard
        label="Saldo devedor"
        :value="brl(summary.saldo_devedor)"
        tone="negative"
        hint="Em aberto + protestado, no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Vendedores"
        :value="num(summary.salespeople_count)"
        hint="Quantidade de vendedores com inadimplência no recorte selecionado."
        hint-scope="all"
      />
    </div>

    <div class="grid grid-cols-1 gap-6" :class="summary.has_detail ? 'lg:grid-cols-2' : ''">
      <ChartCard
        title="Inadimplência por vendedor"
        subtitle="Em aberto + protestado"
        hint="Valor em aberto e protestado por vendedor (barras empilhadas), no recorte."
        hint-scope="all"
      >
        <BaseChart :option="salespeopleOption" :height="440" />
      </ChartCard>
      <ChartCard
        v-if="summary.has_detail"
        title="Em aberto por mês de vencimento"
        hint="Total em aberto agrupado pelo mês de vencimento do título, no recorte."
        hint-scope="all"
      >
        <BaseChart :option="dueMonthOption" :height="440" />
      </ChartCard>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          Detalhamento por vendedor
          <InfoHint
            text="Detalhe da inadimplência por vendedor: em aberto, protestado e saldo devedor."
            scope="all"
          />
        </h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-5 py-3 font-medium">Vendedor</th>
              <th class="px-5 py-3 text-right font-medium">Em aberto</th>
              <th class="px-5 py-3 text-right font-medium">Protestado</th>
              <th class="px-5 py-3 text-right font-medium">Saldo devedor</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="row in bySalesperson" :key="row.name" class="hover:bg-slate-50">
              <td class="px-5 py-2.5 font-medium text-slate-700">
                {{ row.name }}
                <span v-if="row.linked && row.linked.toUpperCase() !== row.name.toUpperCase()" class="ml-1 text-xs text-slate-400">→ {{ row.linked }}</span>
              </td>
              <td class="px-5 py-2.5 text-right tabular-nums" :class="row.open > 0 ? 'text-amber-600' : 'text-slate-300'">{{ brl(row.open) }}</td>
              <td class="px-5 py-2.5 text-right tabular-nums" :class="row.protested > 0 ? 'text-red-600' : 'text-slate-300'">{{ brl(row.protested) }}</td>
              <td class="px-5 py-2.5 text-right font-semibold tabular-nums text-slate-800">{{ brl(row.saldo) }}</td>
            </tr>
            <tr v-if="bySalesperson.length === 0">
              <td colspan="4" class="px-5 py-12 text-center text-slate-400">Nenhuma inadimplência no recorte selecionado.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <p v-if="!summary.has_detail" class="rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-xs text-slate-500">
      Inadimplência disponível apenas no formato resumo (por vendedor). O detalhamento por parceiro, mês de vencimento e
      título aparece quando a sincronização traz os títulos em aberto do ERP.
    </p>
  </div>
</template>
