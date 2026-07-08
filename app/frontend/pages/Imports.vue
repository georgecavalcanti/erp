<script setup lang="ts">
import { ref } from 'vue'
import { Head, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import { num, dateBR } from '@/lib/format'
import type { ImportBatchRow, ImportStatus } from '@/types/models'

defineOptions({ layout: AppLayout })

defineProps<{ batches: ImportBatchRow[] }>()

const fileInput = ref<HTMLInputElement | null>(null)
const form = useForm<{ file: File | null }>({ file: null })

function onFile(event: Event) {
  const target = event.target as HTMLInputElement
  form.file = target.files?.[0] ?? null
}

function submit() {
  form.post('/importacoes', {
    forceFormData: true,
    onSuccess: () => {
      form.reset()
      if (fileInput.value) fileInput.value.value = ''
    },
  })
}

const STATUS: Record<ImportStatus, { label: string; cls: string }> = {
  pending: { label: 'Pendente', cls: 'bg-slate-100 text-slate-600' },
  processing: { label: 'Processando', cls: 'bg-sky-50 text-sky-700' },
  completed: { label: 'Concluído', cls: 'bg-emerald-50 text-emerald-700' },
  failed: { label: 'Falhou', cls: 'bg-red-50 text-red-700' },
}

const KIND_CLS: Record<string, string> = {
  invoices: 'bg-indigo-50 text-indigo-700',
  pending_orders: 'bg-sky-50 text-sky-700',
  delinquency: 'bg-amber-50 text-amber-700',
}
</script>

<template>
  <Head title="Importações" />

  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Importações</h1>
      <p class="text-sm text-slate-500">
        Envie qualquer planilha (.xls, .xlsx, .csv) — o sistema detecta o tipo automaticamente:
        notas/devoluções, pedidos pendentes ou inadimplência.
      </p>
    </div>

    <!-- Upload -->
    <form class="rounded-xl border border-slate-200 bg-white p-6 shadow-sm" @submit.prevent="submit">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-end">
        <div class="flex-1">
          <label class="mb-1 block text-sm font-medium text-slate-600">Planilha</label>
          <input
            ref="fileInput"
            type="file"
            accept=".xls,.xlsx,.csv"
            class="block w-full text-sm text-slate-600 file:mr-4 file:rounded-md file:border-0 file:bg-indigo-50 file:px-4 file:py-2 file:text-sm file:font-medium file:text-indigo-700 hover:file:bg-indigo-100"
            @change="onFile"
          />
          <p v-if="form.progress" class="mt-2 text-xs text-slate-500">
            Enviando… {{ form.progress.percentage }}%
          </p>
        </div>
        <button
          type="submit"
          :disabled="!form.file || form.processing"
          class="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-500 disabled:opacity-50"
        >
          {{ form.processing ? 'Importando…' : 'Importar' }}
        </button>
      </div>
      <p class="mt-3 text-xs text-slate-400">
        A importação é idempotente: reenviar o mesmo período atualiza as notas existentes (por Nº Único) sem duplicar e
        preserva os pagamentos já marcados.
      </p>
    </form>

    <!-- Histórico -->
    <section class="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
      <header class="border-b border-slate-200 px-5 py-3">
        <h3 class="text-sm font-semibold text-slate-700">Histórico</h3>
      </header>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200 text-sm">
          <thead class="bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="px-5 py-3 font-medium">Arquivo</th>
              <th class="px-5 py-3 font-medium">Tipo</th>
              <th class="px-5 py-3 font-medium">Status</th>
              <th class="px-5 py-3 text-right font-medium">Registros</th>
              <th class="px-5 py-3 font-medium">Período / ref.</th>
              <th class="px-5 py-3 font-medium">Enviado</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="batch in batches" :key="batch.id" class="hover:bg-slate-50">
              <td class="px-5 py-3">
                <div class="font-medium text-slate-700">{{ batch.filename }}</div>
                <div v-if="batch.error_message" class="text-xs text-red-500">{{ batch.error_message }}</div>
                <div v-else-if="batch.user" class="text-xs text-slate-400">{{ batch.user }}</div>
              </td>
              <td class="px-5 py-3">
                <span class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium" :class="KIND_CLS[batch.kind] ?? 'bg-slate-100 text-slate-600'">
                  {{ batch.kind_label }}
                </span>
              </td>
              <td class="px-5 py-3">
                <span class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium" :class="STATUS[batch.status].cls">
                  {{ STATUS[batch.status].label }}
                </span>
              </td>
              <td class="px-5 py-3 text-right tabular-nums text-slate-700">{{ num(batch.rows_imported) }}</td>
              <td class="px-5 py-3 text-xs text-slate-500">
                <template v-if="batch.reference_date">até {{ dateBR(batch.reference_date) }}</template>
                <template v-else-if="batch.period_start">{{ dateBR(batch.period_start) }} – {{ dateBR(batch.period_end) }}</template>
                <template v-else>—</template>
              </td>
              <td class="px-5 py-3 tabular-nums text-slate-500">{{ dateBR(batch.created_at) }}</td>
            </tr>
            <tr v-if="batches.length === 0">
              <td colspan="6" class="px-5 py-12 text-center text-slate-400">Nenhuma importação ainda. Envie sua primeira planilha acima.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
