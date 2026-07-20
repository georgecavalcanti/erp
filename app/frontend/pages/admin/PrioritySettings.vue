<script setup lang="ts">
import { Head, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'

defineOptions({ layout: AppLayout })

interface Setting {
  weight_revenue: number; weight_conversion: number; weight_urgency: number; weight_gap: number
  weight_risk: number; weight_margin: number; weight_strategic: number
  daily_capacity: number; recent_contact_days: number; min_margin_percent: number | null
  normalized: Record<string, number>
}

const props = defineProps<{ setting: Setting }>()

const WEIGHTS = [
  { key: 'weight_revenue', norm: 'revenue', label: 'Potencial de receita' },
  { key: 'weight_conversion', norm: 'conversion', label: 'Probabilidade de conversão' },
  { key: 'weight_urgency', norm: 'urgency', label: 'Urgência' },
  { key: 'weight_gap', norm: 'gap', label: 'Contribuição para o gap' },
  { key: 'weight_risk', norm: 'risk', label: 'Risco de perda' },
  { key: 'weight_margin', norm: 'margin', label: 'Margem potencial' },
  { key: 'weight_strategic', norm: 'strategic', label: 'Relevância estratégica' },
] as const

const form = useForm({ ...props.setting })
function save() {
  form.patch('/admin/priorizacao', { preserveScroll: true })
}
</script>

<template>
  <Head title="Priorização" />
  <div class="max-w-2xl space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Configuração da priorização</h1>
      <p class="text-sm text-slate-500">Pesos do score, capacidade diária e limiares das restrições (doc 05.4).</p>
    </div>

    <form class="space-y-6" @submit.prevent="save">
      <div class="rounded-xl border border-slate-200 bg-white p-5">
        <h2 class="mb-3 text-sm font-semibold text-slate-600">Pesos dos fatores</h2>
        <div class="space-y-3">
          <div v-for="w in WEIGHTS" :key="w.key" class="flex items-center gap-3">
            <label class="flex-1 text-sm text-slate-600">{{ w.label }}</label>
            <input v-model.number="form[w.key]" type="number" min="0" max="100"
                   class="w-24 rounded-md border-slate-300 text-right text-sm shadow-sm focus:border-red-500 focus:ring-red-500" />
            <span class="w-16 text-right text-xs text-slate-400">{{ setting.normalized[w.norm] }}%</span>
          </div>
        </div>
        <p class="mt-2 text-xs text-slate-400">Os pesos são normalizados (a % à direita é o peso efetivo no score).</p>
      </div>

      <div class="rounded-xl border border-slate-200 bg-white p-5">
        <h2 class="mb-3 text-sm font-semibold text-slate-600">Capacidade e restrições</h2>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <label class="text-sm text-slate-600">
            Ações por dia
            <input v-model.number="form.daily_capacity" type="number" min="1" class="mt-1 w-full rounded-md border-slate-300 text-sm shadow-sm" />
          </label>
          <label class="text-sm text-slate-600">
            Contato recente (dias)
            <input v-model.number="form.recent_contact_days" type="number" min="0" class="mt-1 w-full rounded-md border-slate-300 text-sm shadow-sm" />
          </label>
          <label class="text-sm text-slate-600">
            Margem mínima (%)
            <input v-model.number="form.min_margin_percent" type="number" step="0.1" placeholder="sem política" class="mt-1 w-full rounded-md border-slate-300 text-sm shadow-sm" />
          </label>
        </div>
      </div>

      <button type="submit" :disabled="form.processing"
              class="rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50">
        Salvar configuração
      </button>
    </form>
  </div>
</template>
