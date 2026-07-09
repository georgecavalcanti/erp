<script setup lang="ts">
import { reactive, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import MultiSelect from '@/components/MultiSelect.vue'
import type { AppliedFilters, FilterOptions } from '@/types/models'

const props = defineProps<{ filters: AppliedFilters; options: FilterOptions }>()

const MONTHS = [
  { id: 1, name: 'Janeiro' },
  { id: 2, name: 'Fevereiro' },
  { id: 3, name: 'Março' },
  { id: 4, name: 'Abril' },
  { id: 5, name: 'Maio' },
  { id: 6, name: 'Junho' },
  { id: 7, name: 'Julho' },
  { id: 8, name: 'Agosto' },
  { id: 9, name: 'Setembro' },
  { id: 10, name: 'Outubro' },
  { id: 11, name: 'Novembro' },
  { id: 12, name: 'Dezembro' },
]

// Modo de recorte temporal: por ano/meses OU por intervalo De/Até (exclusivos).
type PeriodMode = 'months' | 'range'
const periodMode = ref<PeriodMode>(props.filters.start || props.filters.end ? 'range' : 'months')

const state = reactive({
  start: props.filters.start ?? '',
  end: props.filters.end ?? '',
  year: props.filters.year ? String(props.filters.year) : '',
  months: [...(props.filters.months ?? [])],
  company_id: props.filters.company_id ? String(props.filters.company_id) : '',
  salesperson_ids: [...(props.filters.salesperson_ids ?? [])],
  partner_ids: [...(props.filters.partner_ids ?? [])],
})

const hasFilters = () =>
  Boolean(
    state.start ||
      state.end ||
      state.year ||
      state.months.length ||
      state.company_id ||
      state.salesperson_ids.length ||
      state.partner_ids.length,
  )

function apply() {
  const params: Record<string, string | number[]> = {}
  // Envia apenas o recorte do modo ativo — os dois nunca vão juntos.
  if (periodMode.value === 'range') {
    if (state.start) params.start = state.start
    if (state.end) params.end = state.end
  } else {
    if (state.year) params.year = state.year
    if (state.months.length) params.months = state.months
  }
  if (state.company_id) params.company_id = state.company_id
  if (state.salesperson_ids.length) params.salesperson_ids = state.salesperson_ids
  if (state.partner_ids.length) params.partner_ids = state.partner_ids
  router.get(window.location.pathname, params, { preserveState: true, preserveScroll: true, replace: true })
}

function clear() {
  state.start = ''
  state.end = ''
  state.year = ''
  state.months = []
  state.company_id = ''
  state.salesperson_ids = []
  state.partner_ids = []
  periodMode.value = 'months'
  router.get(window.location.pathname, {}, { preserveState: true, preserveScroll: true, replace: true })
}

const field =
  'w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500'
const labelCls = 'mb-1 block text-xs font-medium text-slate-500'
const tab = 'rounded px-3 py-1 text-xs font-medium transition-colors'
const tabActive = 'bg-white text-indigo-600 shadow-sm'
const tabIdle = 'text-slate-500 hover:text-slate-700'
</script>

<template>
  <div class="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
    <div class="mb-3 inline-flex rounded-md border border-slate-200 bg-slate-50 p-0.5">
      <button type="button" :class="[tab, periodMode === 'months' ? tabActive : tabIdle]" @click="periodMode = 'months'">
        Ano / Meses
      </button>
      <button type="button" :class="[tab, periodMode === 'range' ? tabActive : tabIdle]" @click="periodMode = 'range'">
        Intervalo de datas
      </button>
    </div>

    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-6">
      <template v-if="periodMode === 'months'">
        <div>
          <label :class="labelCls">Ano</label>
          <select v-model="state.year" :class="field">
            <option value="">Todos</option>
            <option v-for="y in options.years" :key="y" :value="String(y)">{{ y }}</option>
          </select>
        </div>
        <MultiSelect label="Meses" :options="MONTHS" v-model="state.months" all-label="Todos" />
      </template>
      <template v-else>
        <div>
          <label :class="labelCls">De</label>
          <input v-model="state.start" type="date" :class="field" @keyup.enter="apply" />
        </div>
        <div>
          <label :class="labelCls">Até</label>
          <input v-model="state.end" type="date" :class="field" @keyup.enter="apply" />
        </div>
      </template>

      <div>
        <label :class="labelCls">Empresa</label>
        <select v-model="state.company_id" :class="field">
          <option value="">Todas</option>
          <option v-for="c in options.companies" :key="c.id" :value="String(c.id)">{{ c.name }}</option>
        </select>
      </div>
      <MultiSelect label="Vendedores" :options="options.salespeople" v-model="state.salesperson_ids" searchable all-label="Todos" />
      <MultiSelect label="Parceiros" :options="options.partners" v-model="state.partner_ids" searchable all-label="Todos" />
      <div class="flex items-end gap-2">
        <button
          type="button"
          class="flex-1 rounded-md bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-500"
          @click="apply"
        >
          Aplicar
        </button>
        <button
          v-if="hasFilters()"
          type="button"
          class="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          @click="clear"
        >
          Limpar
        </button>
      </div>
    </div>
  </div>
</template>
