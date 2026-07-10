<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import FilterBar from '@/components/FilterBar.vue'
import KpiCard from '@/components/KpiCard.vue'
import ChartCard from '@/components/ChartCard.vue'
import BaseChart from '@/components/BaseChart.vue'
import InfoHint from '@/components/InfoHint.vue'
import Pagination from '@/components/Pagination.vue'
import { brl, brlCompact, num, dateBR } from '@/lib/format'
import { PALETTE, GRID } from '@/lib/charts'
import type {
  PortfolioSummary,
  PortfolioSalesperson,
  NamedAmount,
  PendingOrderRow,
  Pagination as Pager,
  AppliedFilters,
  FilterOptions,
} from '@/types/models'

defineOptions({ layout: AppLayout })

const props = defineProps<{
  summary: PortfolioSummary
  bySalesperson: PortfolioSalesperson[]
  byPartner: NamedAmount[]
  orders: PendingOrderRow[]
  pagination: Pager
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const salespeopleOption = computed(() => {
  const top = [...props.bySalesperson].slice(0, 12).sort((a, b) => a.total - b.total)
  return {
    grid: { ...GRID, left: 8 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: (p: any) => `<b>${p[0].name}</b><br/>Carteira: ${brl(p[0].value)}` },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: top.map((r) => r.name) },
    series: [{ type: 'bar', data: top.map((r) => r.total), itemStyle: { color: PALETTE[1], borderRadius: [0, 4, 4, 0] }, barMaxWidth: 20 }],
  }
})

const partnerOption = computed(() => {
  const top = [...props.byPartner].slice(0, 12).sort((a, b) => a.amount - b.amount)
  return {
    grid: { ...GRID, left: 8 },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: (p: any) => `<b>${p[0].name}</b><br/>Carteira: ${brl(p[0].value)}` },
    xAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
    yAxis: { type: 'category', data: top.map((r) => r.name) },
    series: [{ type: 'bar', data: top.map((r) => r.amount), itemStyle: { color: PALETTE[5], borderRadius: [0, 4, 4, 0] }, barMaxWidth: 20 }],
  }
})
</script>

<template>
  <Head title="Carteira" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Carteira a faturar</h1>
      <p class="text-sm text-slate-500">Pedidos liberados, pendentes de faturamento · sempre o mês corrente.</p>
    </div>

    <!-- Sem filtro de data: a carteira é snapshot do mês corrente (data não recorta). -->
    <FilterBar :filters="filters" :options="filterOptions" :show-period="false" />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <KpiCard
        label="Total da carteira"
        :value="brl(summary.total)"
        tone="positive"
        hint="Soma dos pedidos liberados e pendentes de faturamento, no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Pedidos"
        :value="num(summary.count)"
        hint="Quantidade de pedidos pendentes de faturamento, no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Ticket médio"
        :value="brl(summary.avg_ticket)"
        hint="Valor total da carteira dividido pela quantidade de pedidos, no recorte."
        hint-scope="all"
      />
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <ChartCard
        title="Carteira por vendedor"
        subtitle="Top 12"
        hint="Valor da carteira pendente somado por vendedor (12 maiores), no recorte."
        hint-scope="all"
      >
        <BaseChart :option="salespeopleOption" :height="360" />
      </ChartCard>
      <ChartCard
        title="Carteira por parceiro"
        subtitle="Top 12"
        hint="Valor da carteira pendente somado por parceiro (12 maiores), no recorte."
        hint-scope="all"
      >
        <BaseChart :option="partnerOption" :height="360" />
      </ChartCard>
    </div>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          Pedidos pendentes
          <InfoHint
            text="Lista dos pedidos liberados aguardando faturamento, no recorte selecionado."
            scope="all"
          />
        </h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-5 py-3 font-medium">Pedido</th>
              <th class="px-5 py-3 font-medium">Parceiro</th>
              <th class="px-5 py-3 font-medium">Vendedor</th>
              <th class="px-5 py-3 font-medium">Data</th>
              <th class="px-5 py-3 font-medium">Entrega</th>
              <th class="px-5 py-3 text-right font-medium">Valor</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="o in orders" :key="o.id" class="hover:bg-slate-50">
              <td class="px-5 py-3 font-medium text-slate-700">{{ o.external_uid }}</td>
              <td class="px-5 py-3 text-slate-600">{{ o.partner ?? '—' }}</td>
              <td class="px-5 py-3 text-slate-500">{{ o.salesperson ?? '—' }}</td>
              <td class="px-5 py-3 tabular-nums text-slate-500">{{ dateBR(o.negotiation_date) }}</td>
              <td class="px-5 py-3 text-xs text-slate-500">{{ o.delivery_type ?? '—' }}</td>
              <td class="px-5 py-3 text-right font-medium tabular-nums text-slate-800">{{ brl(o.total_value) }}</td>
            </tr>
            <tr v-if="orders.length === 0">
              <td colspan="6" class="px-5 py-12 text-center text-slate-400">Nenhum pedido pendente no recorte selecionado.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer class="border-t border-slate-200 px-5 py-3">
        <Pagination :pagination="pagination" />
      </footer>
    </section>
  </div>
</template>
