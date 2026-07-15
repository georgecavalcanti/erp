<script setup lang="ts">
import { ref } from 'vue'
import { Head, router, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import { brl } from '@/lib/format'

defineOptions({ layout: AppLayout })

interface Option { id: number; name: string }
interface KindOption { value: string; label: string }
interface GoalRow {
  id: number
  salesperson_id: number
  salesperson: string
  period: string
  kind: string
  kind_label: string
  amount: number | null
  min_margin_percent: number | null
}

const props = defineProps<{
  goals: GoalRow[]
  filters: { period: string; salesperson_id: number | null }
  options: { salespeople: Option[]; kinds: KindOption[] }
}>()

const periodFilter = ref(props.filters.period)
const sellerFilter = ref<number | null>(props.filters.salesperson_id)

function applyFilters() {
  router.get('/admin/metas', {
    period: periodFilter.value || undefined,
    salesperson_id: sellerFilter.value || undefined,
  }, { preserveState: true })
}

const editingId = ref<number | null>(null)
const form = useForm({
  salesperson_id: null as number | null,
  period: props.filters.period,
  kind: 'revenue',
  amount: null as number | null,
  min_margin_percent: null as number | null,
})

function edit(goal: GoalRow) {
  editingId.value = goal.id
  form.salesperson_id = goal.salesperson_id
  form.period = goal.period
  form.kind = goal.kind
  form.amount = goal.amount
  form.min_margin_percent = goal.min_margin_percent
}

function resetForm() {
  editingId.value = null
  form.reset()
  form.period = props.filters.period
}

function submit() {
  if (editingId.value) {
    form.patch(`/admin/metas/${editingId.value}`, { onSuccess: () => resetForm() })
  } else {
    form.post('/admin/metas', { onSuccess: () => resetForm() })
  }
}

function remove(goal: GoalRow) {
  if (confirm(`Remover a meta de ${goal.salesperson} (${goal.kind_label}, ${goal.period})?`)) {
    router.delete(`/admin/metas/${goal.id}`)
  }
}
</script>

<template>
  <Head title="Metas" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Metas</h1>
      <p class="text-sm text-slate-500">Metas por vendedor e mês (o ERP não gere metas — cadastro no FV360)</p>
    </div>

    <!-- Filtros -->
    <div class="flex flex-wrap items-end gap-3">
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Mês</label>
        <input v-model="periodFilter" type="month" class="rounded-md border-slate-300 text-sm shadow-sm" @change="applyFilters" />
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Vendedor</label>
        <select v-model="sellerFilter" class="rounded-md border-slate-300 text-sm shadow-sm" @change="applyFilters">
          <option :value="null">Todos</option>
          <option v-for="s in options.salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
    </div>

    <!-- Form nova/editar meta -->
    <form class="grid grid-cols-1 gap-3 rounded-lg border border-slate-200 bg-white p-4 sm:grid-cols-6" @submit.prevent="submit">
      <div class="sm:col-span-2">
        <label class="mb-1 block text-xs font-medium text-slate-500">Vendedor</label>
        <select v-model="form.salesperson_id" required :disabled="!!editingId"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm disabled:bg-slate-100">
          <option :value="null">— selecione —</option>
          <option v-for="s in options.salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Mês</label>
        <input v-model="form.period" type="month" required :disabled="!!editingId"
               class="w-full rounded-md border-slate-300 text-sm shadow-sm disabled:bg-slate-100" />
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Tipo</label>
        <select v-model="form.kind" :disabled="!!editingId" class="w-full rounded-md border-slate-300 text-sm shadow-sm disabled:bg-slate-100">
          <option v-for="k in options.kinds" :key="k.value" :value="k.value">{{ k.label }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Alvo (R$)</label>
        <input v-model="form.amount" type="number" step="0.01" min="0" class="w-full rounded-md border-slate-300 text-sm shadow-sm" />
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Margem mín. (%)</label>
        <input v-model="form.min_margin_percent" type="number" step="0.01" min="0" class="w-full rounded-md border-slate-300 text-sm shadow-sm" />
      </div>
      <div class="flex items-end gap-2 sm:col-span-6">
        <button type="submit" :disabled="form.processing"
                class="rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50">
          {{ editingId ? 'Atualizar meta' : 'Adicionar meta' }}
        </button>
        <button v-if="editingId" type="button" class="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50" @click="resetForm">
          Cancelar edição
        </button>
        <p v-if="form.errors.kind" class="text-xs text-red-600">{{ form.errors.kind }}</p>
      </div>
    </form>

    <div class="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
          <tr>
            <th class="px-4 py-3">Vendedor</th>
            <th class="px-4 py-3">Mês</th>
            <th class="px-4 py-3">Tipo</th>
            <th class="px-4 py-3 text-right">Alvo</th>
            <th class="px-4 py-3 text-right">Margem mín.</th>
            <th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="g in goals" :key="g.id" class="hover:bg-slate-50">
            <td class="px-4 py-3 font-medium text-slate-700">{{ g.salesperson }}</td>
            <td class="px-4 py-3 text-slate-600">{{ g.period }}</td>
            <td class="px-4 py-3 text-slate-600">{{ g.kind_label }}</td>
            <td class="px-4 py-3 text-right text-slate-700">{{ g.amount != null ? brl(g.amount) : '—' }}</td>
            <td class="px-4 py-3 text-right text-slate-600">{{ g.min_margin_percent != null ? `${g.min_margin_percent}%` : '—' }}</td>
            <td class="px-4 py-3 text-right whitespace-nowrap">
              <button class="text-sm font-medium text-indigo-600 hover:underline" @click="edit(g)">Editar</button>
              <button class="ml-3 text-sm font-medium text-red-600 hover:underline" @click="remove(g)">Remover</button>
            </td>
          </tr>
          <tr v-if="goals.length === 0">
            <td colspan="6" class="px-4 py-8 text-center text-slate-400">Nenhuma meta para este mês.</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
