<script setup lang="ts">
import { reactive } from 'vue'
import { router } from '@inertiajs/vue3'
import type { AppliedFilters, FilterOptions } from '@/types/models'

const props = defineProps<{ filters: AppliedFilters; options: FilterOptions }>()

const state = reactive({
  start: props.filters.start ?? '',
  end: props.filters.end ?? '',
  company_id: props.filters.company_id ? String(props.filters.company_id) : '',
  salesperson_id: props.filters.salesperson_id ? String(props.filters.salesperson_id) : '',
  partner_id: props.filters.partner_id ? String(props.filters.partner_id) : '',
})

const hasFilters = () =>
  Boolean(state.start || state.end || state.company_id || state.salesperson_id || state.partner_id)

function apply() {
  const params: Record<string, string> = {}
  if (state.start) params.start = state.start
  if (state.end) params.end = state.end
  if (state.company_id) params.company_id = state.company_id
  if (state.salesperson_id) params.salesperson_id = state.salesperson_id
  if (state.partner_id) params.partner_id = state.partner_id
  router.get(window.location.pathname, params, { preserveState: true, preserveScroll: true, replace: true })
}

function clear() {
  state.start = ''
  state.end = ''
  state.company_id = ''
  state.salesperson_id = ''
  state.partner_id = ''
  router.get(window.location.pathname, {}, { preserveState: true, preserveScroll: true, replace: true })
}

const field =
  'w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500'
const labelCls = 'mb-1 block text-xs font-medium text-slate-500'
</script>

<template>
  <div class="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-6">
      <div>
        <label :class="labelCls">De</label>
        <input v-model="state.start" type="date" :class="field" @keyup.enter="apply" />
      </div>
      <div>
        <label :class="labelCls">Até</label>
        <input v-model="state.end" type="date" :class="field" @keyup.enter="apply" />
      </div>
      <div>
        <label :class="labelCls">Empresa</label>
        <select v-model="state.company_id" :class="field" @change="apply">
          <option value="">Todas</option>
          <option v-for="c in options.companies" :key="c.id" :value="String(c.id)">{{ c.name }}</option>
        </select>
      </div>
      <div>
        <label :class="labelCls">Vendedor</label>
        <select v-model="state.salesperson_id" :class="field" @change="apply">
          <option value="">Todos</option>
          <option v-for="s in options.salespeople" :key="s.id" :value="String(s.id)">{{ s.name }}</option>
        </select>
      </div>
      <div>
        <label :class="labelCls">Parceiro</label>
        <select v-model="state.partner_id" :class="field" @change="apply">
          <option value="">Todos</option>
          <option v-for="p in options.partners" :key="p.id" :value="String(p.id)">{{ p.name }}</option>
        </select>
      </div>
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
