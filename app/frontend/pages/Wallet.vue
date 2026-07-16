<script setup lang="ts">
import { ref } from 'vue'
import { Head, Link, router } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import Pagination from '@/components/Pagination.vue'
import { brl } from '@/lib/format'
import type { Pagination as PaginationType } from '@/types/models'

defineOptions({ layout: AppLayout })

interface Client {
  id: number
  name: string
  city: string | null
  state: string | null
  blocked: boolean
  revenue_12m: number
  last_purchase_on: string | null
  days_since: number | null
  segment: string
}

const props = defineProps<{
  clients: Client[]
  segments: Record<string, number>
  summary: { total: number; revenue_12m: number }
  pagination: PaginationType
  filters: { q: string | null; segment: string | null }
}>()

const SEGMENTS = [
  { key: 'ativo', label: 'Ativos', tone: 'text-emerald-700 bg-emerald-50' },
  { key: 'atencao', label: 'Em atenção', tone: 'text-amber-700 bg-amber-50' },
  { key: 'inativo', label: 'Inativos', tone: 'text-red-700 bg-red-50' },
  { key: 'sem_compra', label: 'Sem compra', tone: 'text-slate-600 bg-slate-100' },
] as const

const q = ref(props.filters.q ?? '')

function apply(extra: Record<string, string | undefined> = {}) {
  router.get('/minha-carteira', { q: q.value || undefined, segment: props.filters.segment || undefined, ...extra },
    { preserveState: true, preserveScroll: true })
}
function toggleSegment(seg: string) {
  apply({ segment: props.filters.segment === seg ? undefined : seg })
}
function segMeta(key: string) {
  return SEGMENTS.find((s) => s.key === key)
}
</script>

<template>
  <Head title="Minha carteira" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Minha carteira</h1>
      <p class="text-sm text-slate-500">
        {{ summary.total }} clientes · {{ brl(summary.revenue_12m) }} nos últimos 12 meses
      </p>
    </div>

    <!-- Segmentos por recência -->
    <div class="flex flex-wrap gap-2">
      <button
        v-for="s in SEGMENTS"
        :key="s.key"
        class="rounded-full px-3 py-1.5 text-sm font-medium transition"
        :class="[s.tone, filters.segment === s.key ? 'ring-2 ring-offset-1 ring-slate-400' : 'opacity-80 hover:opacity-100']"
        @click="toggleSegment(s.key)"
      >
        {{ s.label }} · {{ segments[s.key] ?? 0 }}
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
            <th class="px-4 py-3">Local</th>
            <th class="px-4 py-3">Situação</th>
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
            </td>
            <td class="px-4 py-3 text-slate-600">{{ [c.city, c.state].filter(Boolean).join(' / ') || '—' }}</td>
            <td class="px-4 py-3">
              <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="segMeta(c.segment)?.tone">
                {{ segMeta(c.segment)?.label.replace(/s$/, '') }}
              </span>
            </td>
            <td class="px-4 py-3 text-slate-500">
              {{ c.last_purchase_on || '—' }}
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
