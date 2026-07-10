<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import FilterBar from '@/components/FilterBar.vue'
import InfoHint from '@/components/InfoHint.vue'
import { brl, brlCompact, dateBR } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'
import type { SituationRow, SituationTotals, AppliedFilters, FilterOptions } from '@/types/models'

defineOptions({ layout: AppLayout })

const props = defineProps<{
  rows: SituationRow[]
  totals: SituationTotals
  delinquencyReference: string | null
  hasDelinquency: boolean
  hasPortfolio: boolean
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const chartOption = computed(() => {
  const top = [...props.rows].sort((a, b) => a.liquido - b.liquido).slice(-12)
  return {
    color: [PALETTE[2], PALETTE[1], PALETTE[3]],
    grid: { ...GRID, left: 8 },
    legend: { top: 0, icon: 'circle', textStyle: { fontSize: 11 } },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, valueFormatter: (v: number) => brl(v) },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: top.map((r) => r.name) },
    series: [
      { name: 'Líquido faturado', type: 'bar', data: top.map((r) => r.liquido), barMaxWidth: 10, itemStyle: { borderRadius: [0, 3, 3, 0] } },
      { name: 'Carteira', type: 'bar', data: top.map((r) => r.carteira), barMaxWidth: 10, itemStyle: { borderRadius: [0, 3, 3, 0] } },
      { name: 'Inadimplência', type: 'bar', data: top.map((r) => r.inad_aberto), barMaxWidth: 10, itemStyle: { borderRadius: [0, 3, 3, 0] } },
    ],
  }
})

const cols: { key: keyof SituationTotals; label: string; tone?: string }[] = [
  { key: 'faturamento', label: 'Faturamento' },
  { key: 'devolucoes', label: 'Devoluções', tone: 'text-red-600' },
  { key: 'liquido', label: 'Líquido' },
  { key: 'comissao', label: 'Comissão' },
  { key: 'carteira', label: 'Carteira' },
  { key: 'inad_aberto', label: 'Inad. aberto', tone: 'text-amber-600' },
  { key: 'protestado', label: 'Protestado', tone: 'text-red-600' },
  { key: 'saldo', label: 'Saldo devedor', tone: 'text-red-700' },
]
</script>

<template>
  <Head title="Situação geral" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Situação geral</h1>
      <p class="text-sm text-slate-500">
        Reconciliação por vendedor: faturamento, carteira a faturar e inadimplência.
        <span v-if="delinquencyReference" class="text-slate-400">· inadimplência até {{ dateBR(delinquencyReference) }}</span>
      </p>
    </div>

    <FilterBar :filters="filters" :options="filterOptions" />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <KpiCard
        label="Faturamento líquido"
        :value="brl(totals.liquido)"
        tone="positive"
        hint="Vendas menos devoluções por vendedor, no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Carteira a faturar"
        :value="brl(totals.carteira)"
        hint="Pedidos pendentes de faturamento, recortados por empresa, vendedores e parceiros. A data não se aplica (snapshot do mês corrente)."
        hint-scope="partial"
        hint-note="Empresa, vendedor e parceiro (não período)"
      />
      <KpiCard
        label="Inadimplência (aberto)"
        :value="brl(totals.inad_aberto)"
        tone="warning"
        hint="Títulos em aberto por vendedor (snapshot), no recorte de vendedor e parceiro. O período não se aplica."
        hint-scope="partial"
        hint-note="Vendedor e parceiro (não período)"
      />
      <KpiCard
        label="Saldo devedor"
        :value="brl(totals.saldo)"
        tone="negative"
        hint="Em aberto + protestado por vendedor (snapshot), no recorte de vendedor e parceiro."
        hint-scope="partial"
        hint-note="Vendedor e parceiro (não período)"
      />
    </div>

    <ChartCard
      title="Líquido × Carteira × Inadimplência"
      subtitle="Top 12 vendedores por líquido faturado"
      hint="Compara, por vendedor, faturamento líquido, carteira e inadimplência. Líquido segue todos os filtros; carteira e inadimplência não respondem à data (snapshots)."
      hint-scope="partial"
      hint-note="Carteira/Inadimplência: sem período"
    >
      <BaseChart :option="chartOption" :height="420" />
    </ChartCard>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          Detalhamento por vendedor
          <InfoHint
            text="Uma linha por vendedor com faturamento, carteira e inadimplência. Faturamento segue todos os filtros; carteira e inadimplência não respondem à data (snapshots)."
            scope="partial"
            scope-note="Carteira/Inadimplência: sem período"
          />
        </h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="sticky left-0 z-10 bg-slate-50 px-4 py-3 font-medium">Vendedor</th>
              <th v-for="c in cols" :key="c.key" class="whitespace-nowrap px-3 py-3 text-right font-medium">{{ c.label }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="row in rows" :key="row.name" class="bg-white hover:bg-slate-50">
              <td class="sticky left-0 z-10 border-r border-slate-100 bg-inherit px-4 py-2.5 font-medium text-slate-700">
                {{ row.name }}
              </td>
              <td
                v-for="c in cols"
                :key="c.key"
                class="whitespace-nowrap px-3 py-2.5 text-right tabular-nums"
                :class="row[c.key] !== 0 ? (c.tone ?? 'text-slate-600') : 'text-slate-300'"
              >
                {{ brl(row[c.key] as number) }}
              </td>
            </tr>
          </tbody>
          <tfoot class="border-t-2 border-slate-200 bg-slate-50 font-semibold text-slate-800">
            <tr>
              <td class="sticky left-0 z-10 border-r border-slate-100 bg-slate-50 px-4 py-3">Total</td>
              <td v-for="c in cols" :key="c.key" class="whitespace-nowrap px-3 py-3 text-right tabular-nums">
                {{ brl(totals[c.key] as number) }}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>
  </div>
</template>
