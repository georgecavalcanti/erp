<script setup lang="ts">
import { ref } from 'vue'
import { Head, Link, router } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import Pagination from '@/components/Pagination.vue'
import { brl, dateBR } from '@/lib/format'
import type { Pagination as PaginationType } from '@/types/models'

defineOptions({ layout: AppLayout })

interface Signal {
  key: string
  label: string
  severity: string
}
interface Client {
  id: number
  name: string
  city: string | null
  state: string | null
  blocked: boolean
  revenue_12m: number
  last_purchase_on: string | null
  days_since: number | null
  status: string | null
  status_label: string | null
  signals: Signal[]
  repurchase_overdue: number
}

const props = defineProps<{
  clients: Client[]
  statuses: Record<string, number>
  summary: { total: number; revenue_12m: number; repurchase_overdue: number }
  pagination: PaginationType
  filters: { q: string | null; status: string | null }
}>()

// Os 6 status do motor de risco (doc 05.3), na ordem saudável → crítico.
const STATUSES = [
  { key: 'saudavel', label: 'Saudável', tone: 'text-emerald-700 bg-emerald-50' },
  { key: 'em_expansao', label: 'Em expansão', tone: 'text-teal-700 bg-teal-50' },
  { key: 'novo_em_ativacao', label: 'Novo em ativação', tone: 'text-sky-700 bg-sky-50' },
  { key: 'em_atencao', label: 'Em atenção', tone: 'text-amber-700 bg-amber-50' },
  { key: 'em_risco', label: 'Em risco', tone: 'text-red-700 bg-red-50' },
  { key: 'inativo', label: 'Inativo', tone: 'text-slate-600 bg-slate-100' },
] as const

// Tom dos sinais por severidade.
const SIGNAL_TONE: Record<string, string> = {
  high: 'text-red-700 bg-red-50 ring-red-200',
  medium: 'text-amber-700 bg-amber-50 ring-amber-200',
  low: 'text-slate-600 bg-slate-100 ring-slate-200',
  info: 'text-teal-700 bg-teal-50 ring-teal-200',
}

const q = ref(props.filters.q ?? '')

function apply(extra: Record<string, string | undefined> = {}) {
  router.get('/minha-carteira', { q: q.value || undefined, status: props.filters.status || undefined, ...extra },
    { preserveState: true, preserveScroll: true })
}
function toggleStatus(status: string) {
  apply({ status: props.filters.status === status ? undefined : status })
}
function statusMeta(key: string | null) {
  return STATUSES.find((s) => s.key === key)
}
</script>

<template>
  <Head title="Minha carteira" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Minha carteira</h1>
      <p class="text-sm text-slate-500">
        {{ summary.total }} clientes · {{ brl(summary.revenue_12m) }} nos últimos 12 meses
        <span v-if="summary.repurchase_overdue > 0" class="ml-1 font-medium text-amber-700">
          · {{ summary.repurchase_overdue }} com recompra atrasada
        </span>
      </p>
    </div>

    <!-- Status de risco (Sprint 6) -->
    <div class="flex flex-wrap gap-2">
      <button
        v-for="s in STATUSES"
        :key="s.key"
        class="rounded-full px-3 py-1.5 text-sm font-medium transition"
        :class="[s.tone, filters.status === s.key ? 'ring-2 ring-offset-1 ring-slate-400' : 'opacity-80 hover:opacity-100']"
        @click="toggleStatus(s.key)"
      >
        {{ s.label }} · {{ statuses[s.key] ?? 0 }}
      </button>
    </div>

    <!-- Busca -->
    <div class="flex gap-2">
      <input
        v-model="q"
        type="search"
        placeholder="Buscar cliente…"
        class="w-full max-w-sm rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
        @keyup.enter="apply()"
      />
      <button class="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50" @click="apply()">
        Buscar
      </button>
    </div>

    <div class="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
          <tr>
            <th class="px-4 py-3">Cliente</th>
            <th class="px-4 py-3">Status</th>
            <th class="px-4 py-3">Sinais</th>
            <th class="px-4 py-3">Última compra</th>
            <th class="px-4 py-3 text-right">Receita 12m</th>
            <th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="c in clients" :key="c.id" class="hover:bg-slate-50">
            <td class="px-4 py-3 font-medium text-slate-700">
              {{ c.name }}
              <span v-if="c.blocked" class="ml-1 rounded bg-red-100 px-1.5 py-0.5 text-xs text-red-700">bloqueado</span>
              <div class="text-xs font-normal text-slate-400">{{ [c.city, c.state].filter(Boolean).join(' / ') || '—' }}</div>
            </td>
            <td class="px-4 py-3">
              <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="statusMeta(c.status)?.tone">
                {{ c.status_label ?? '—' }}
              </span>
            </td>
            <td class="px-4 py-3">
              <div class="flex flex-wrap gap-1">
                <span
                  v-for="sig in c.signals"
                  :key="sig.key"
                  class="rounded px-1.5 py-0.5 text-xs font-medium ring-1"
                  :class="SIGNAL_TONE[sig.severity] ?? SIGNAL_TONE.low"
                >
                  {{ sig.label }}
                </span>
                <span v-if="c.signals.length === 0" class="text-xs text-slate-300">—</span>
              </div>
            </td>
            <td class="px-4 py-3 text-slate-500">
              {{ c.last_purchase_on ? dateBR(c.last_purchase_on) : '—' }}
              <span v-if="c.days_since != null" class="text-xs text-slate-400">({{ c.days_since }}d)</span>
            </td>
            <td class="px-4 py-3 text-right tabular-nums text-slate-700">{{ brl(c.revenue_12m) }}</td>
            <td class="px-4 py-3 text-right">
              <Link :href="`/clientes/${c.id}`" class="text-sm font-medium text-indigo-600 hover:underline">Abrir 360</Link>
            </td>
          </tr>
          <tr v-if="clients.length === 0">
            <td colspan="6" class="px-4 py-8 text-center text-slate-400">Nenhum cliente neste filtro.</td>
          </tr>
        </tbody>
      </table>
    </div>

    <Pagination v-if="pagination.pages > 1" :pagination="pagination" />
  </div>
</template>
