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
import { brl, num, dateBR, monthLabel, percent, brlCompact } from '@/lib/format'
import { STATUS_COLORS, GRID } from '@/lib/charts'
import type {
  Summary,
  MonthlyRow,
  InvoiceRow,
  Pagination as Pager,
  AppliedFilters,
  FilterOptions,
} from '@/types/models'

defineOptions({ layout: AppLayout })

const props = defineProps<{
  summary: Summary
  monthly: MonthlyRow[]
  invoices: InvoiceRow[]
  pagination: Pager
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()

const returnRate = computed(() =>
  props.summary.gross_sales > 0 ? (props.summary.returns_total / props.summary.gross_sales) * 100 : 0,
)

const monthlyOption = computed(() => ({
  color: [STATUS_COLORS.overdue],
  grid: GRID,
  tooltip: { trigger: 'axis', valueFormatter: (v: number) => brl(v) },
  xAxis: { type: 'category', data: props.monthly.map((r) => monthLabel(r.month)) },
  yAxis: { type: 'value', axisLabel: { formatter: (v: number) => brlCompact(v) } },
  series: [
    {
      type: 'bar',
      name: 'Devoluções',
      data: props.monthly.map((r) => r.returns),
      barMaxWidth: 48,
      itemStyle: { borderRadius: [4, 4, 0, 0] },
    },
  ],
}))
</script>

<template>
  <Head title="Devoluções" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Devoluções</h1>
      <p class="text-sm text-slate-500">Notas classificadas como devolução (por tipo de operação).</p>
    </div>

    <FilterBar :filters="filters" :options="filterOptions" />

    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <KpiCard
        label="Total devolvido"
        :value="brl(summary.returns_total)"
        :tone="summary.returns_total > 0 ? 'negative' : 'default'"
        hint="Soma das notas de devolução no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="Nº devoluções"
        :value="num(pagination.total)"
        hint="Quantidade de notas de devolução no recorte selecionado."
        hint-scope="all"
      />
      <KpiCard
        label="% sobre bruto"
        :value="percent(returnRate)"
        hint="Devoluções como percentual do faturamento bruto, no recorte."
        hint-scope="all"
      />
      <KpiCard
        label="Faturamento líquido"
        :value="brl(summary.net_revenue)"
        tone="positive"
        hint="Vendas menos devoluções no recorte selecionado."
        hint-scope="all"
      />
    </div>

    <ChartCard
      title="Devoluções mês a mês"
      hint="Valor devolvido por mês, no recorte selecionado."
      hint-scope="all"
    >
      <BaseChart :option="monthlyOption" :height="300" />
    </ChartCard>

    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          Notas de devolução
          <InfoHint text="Lista das notas classificadas como devolução no recorte selecionado." scope="all" />
        </h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-5 py-3 font-medium">Nota</th>
              <th class="px-5 py-3 font-medium">Parceiro</th>
              <th class="px-5 py-3 font-medium">Vendedor</th>
              <th class="px-5 py-3 font-medium">Emissão</th>
              <th class="px-5 py-3 font-medium">Operação</th>
              <th class="px-5 py-3 text-right font-medium">Valor</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="inv in invoices" :key="inv.id" class="hover:bg-slate-50">
              <td class="px-5 py-3 font-medium text-slate-700">{{ inv.invoice_number ?? inv.external_uid }}</td>
              <td class="px-5 py-3 text-slate-600">{{ inv.partner ?? '—' }}</td>
              <td class="px-5 py-3 text-slate-500">{{ inv.salesperson ?? '—' }}</td>
              <td class="px-5 py-3 tabular-nums text-slate-500">{{ dateBR(inv.negotiation_date) }}</td>
              <td class="px-5 py-3 text-xs text-slate-500">{{ inv.payment_terms ?? '—' }}</td>
              <td class="px-5 py-3 text-right font-medium tabular-nums text-red-600">{{ brl(inv.total_value) }}</td>
            </tr>
            <tr v-if="invoices.length === 0">
              <td colspan="6" class="px-5 py-12 text-center text-slate-400">
                Nenhuma devolução no período. Quando a planilha trouxer notas com “DEVOLUÇÃO” no tipo de operação, elas aparecem aqui.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer v-if="pagination.total > 0" class="border-t border-slate-200 px-5 py-3">
        <Pagination :pagination="pagination" />
      </footer>
    </section>
  </div>
</template>
