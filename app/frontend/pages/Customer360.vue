<script setup lang="ts">
import { computed } from 'vue'
import { Head, Link, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import KpiCard from '@/components/KpiCard.vue'
import { brl } from '@/lib/format'

defineOptions({ layout: AppLayout })

interface Identification {
  id: number; external_code: number; name: string; cnpj: string | null
  city: string | null; state: string | null; segment: string | null
  active: boolean; blocked: boolean; block_reason: string | null
  salesperson: string | null; last_negotiation_on: string | null
}
interface Summary {
  revenue_total: number; revenue_12m: number; margin_total: number; margin_percent: number | null
  invoice_count: number; avg_ticket: number; last_purchase_on: string | null; days_since_last: number | null
  purchases_12m: number; active_months_12m: number; avg_interval_days: number | null
}
interface KindOption { value: string; label: string }

const props = defineProps<{
  identification: Identification
  summary: Summary
  monthly: { month: string; net: number; margin: number }[]
  mix: { category: string; revenue: number; share: number }[]
  topProducts: { product: string; revenue: number; available: number | null; stock_synced_at: string | null }[]
  financial: { blocked: boolean; block_reason: string | null; overdue_open: number; overdue_protested: number; overdue_total: number }
  openOrders: { external_uid: number; negotiation_date: string | null; total_value: number }[]
  activities: { id: number; kind: string; channel: string | null; notes: string | null; occurred_at: string; user: string | null }[]
  activityKinds: KindOption[]
}>()

const maxNet = computed(() => Math.max(1, ...props.monthly.map((m) => Math.abs(m.net))))
const kindLabel = (k: string) => props.activityKinds.find((o) => o.value === k)?.label ?? k

const form = useForm({ partner_id: props.identification.id, kind: 'contact', channel: '', notes: '' })
function register() {
  form.post('/atividades', { preserveScroll: true, onSuccess: () => form.reset('notes', 'channel') })
}
function fmtDateTime(iso: string) {
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <Head :title="identification.name" />
  <div class="space-y-6">
    <!-- Cabeçalho -->
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <div class="flex items-center gap-2">
          <h1 class="text-xl font-semibold text-slate-800">{{ identification.name }}</h1>
          <span v-if="identification.blocked" class="rounded bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
            bloqueado
          </span>
          <span v-else-if="!identification.active" class="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-500">inativo</span>
        </div>
        <p class="text-sm text-slate-500">
          #{{ identification.external_code }}
          <span v-if="identification.city"> · {{ identification.city }}/{{ identification.state }}</span>
          <span v-if="identification.segment"> · {{ identification.segment }}</span>
          <span v-if="identification.salesperson"> · vendedor {{ identification.salesperson }}</span>
        </p>
      </div>
      <Link href="/minha-carteira" class="text-sm font-medium text-slate-500 hover:underline">← Minha carteira</Link>
    </div>

    <!-- KPIs -->
    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <KpiCard label="Receita 12m" :value="brl(summary.revenue_12m)"
               :sub="`${summary.purchases_12m} compras · ${summary.active_months_12m} meses`" tone="positive" />
      <KpiCard label="Receita total" :value="brl(summary.revenue_total)" :sub="`${summary.invoice_count} notas`" />
      <KpiCard label="Margem" :value="summary.margin_percent != null ? `${summary.margin_percent}%` : '—'"
               :sub="brl(summary.margin_total)" />
      <KpiCard label="Ticket médio" :value="brl(summary.avg_ticket)"
               :sub="summary.avg_interval_days != null ? `compra a cada ${summary.avg_interval_days}d` : '—'" />
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
      <!-- Evolução + mix -->
      <div class="space-y-6 lg:col-span-2">
        <div class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="mb-3 text-sm font-semibold text-slate-600">Evolução mensal (líquido)</h2>
          <div class="flex items-end gap-1" style="height: 120px">
            <div v-for="m in monthly" :key="m.month" class="flex flex-1 flex-col items-center justify-end gap-1" :title="`${m.month}: ${brl(m.net)}`">
              <div class="w-full rounded-t bg-indigo-400" :style="{ height: Math.round((Math.abs(m.net) / maxNet) * 100) + '%' }"></div>
              <span class="text-[10px] text-slate-400">{{ m.month.slice(5) }}</span>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="mb-3 text-sm font-semibold text-slate-600">Mix por categoria</h2>
          <div v-if="mix.length" class="space-y-2">
            <div v-for="m in mix" :key="m.category">
              <div class="flex justify-between text-sm">
                <span class="text-slate-600">{{ m.category }}</span>
                <span class="tabular-nums text-slate-500">{{ brl(m.revenue) }} · {{ m.share }}%</span>
              </div>
              <div class="mt-0.5 h-2 rounded-full bg-slate-100">
                <div class="h-full rounded-full bg-emerald-400" :style="{ width: m.share + '%' }"></div>
              </div>
            </div>
          </div>
          <p v-else class="text-sm text-slate-400">Sem itens registrados.</p>
        </div>

        <div class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="mb-3 text-sm font-semibold text-slate-600">Produtos mais comprados</h2>
          <ul v-if="topProducts.length" class="space-y-1.5 text-sm">
            <li v-for="p in topProducts" :key="p.product" class="flex items-center justify-between gap-2">
              <span class="min-w-0 flex-1 truncate text-slate-600">{{ p.product }}</span>
              <span class="shrink-0 text-right">
                <span class="tabular-nums text-slate-700">{{ brl(p.revenue) }}</span>
                <span
                  v-if="p.available != null"
                  class="ml-2 inline-block rounded px-1.5 py-0.5 text-xs"
                  :class="p.available > 0 ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'"
                  :title="p.stock_synced_at ? `estoque de ${new Date(p.stock_synced_at).toLocaleString('pt-BR')}` : ''"
                >
                  {{ p.available > 0 ? `${p.available} em estoque` : 'sem estoque' }}
                </span>
              </span>
            </li>
          </ul>
          <p v-else class="text-sm text-slate-400">Sem itens registrados.</p>
        </div>
      </div>

      <!-- Financeiro + pedidos + atividades -->
      <div class="space-y-6">
        <div class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="mb-3 text-sm font-semibold text-slate-600">Financeiro</h2>
          <dl class="space-y-1 text-sm">
            <div class="flex justify-between"><dt class="text-slate-500">Inadimplência aberta</dt>
              <dd class="tabular-nums" :class="financial.overdue_open > 0 ? 'text-amber-600' : 'text-slate-700'">{{ brl(financial.overdue_open) }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Protestado</dt>
              <dd class="tabular-nums" :class="financial.overdue_protested > 0 ? 'text-red-600' : 'text-slate-700'">{{ brl(financial.overdue_protested) }}</dd></div>
            <div v-if="financial.blocked" class="mt-2 rounded bg-red-50 px-2 py-1 text-xs text-red-700">
              Bloqueado{{ financial.block_reason ? `: ${financial.block_reason}` : '' }}
            </div>
          </dl>
        </div>

        <div class="rounded-xl border border-slate-200 bg-white p-5">
          <h2 class="mb-3 text-sm font-semibold text-slate-600">Pedidos a faturar</h2>
          <ul v-if="openOrders.length" class="space-y-1 text-sm">
            <li v-for="o in openOrders" :key="o.external_uid" class="flex justify-between">
              <span class="text-slate-500">#{{ o.external_uid }} · {{ o.negotiation_date }}</span>
              <span class="tabular-nums text-slate-700">{{ brl(o.total_value) }}</span>
            </li>
          </ul>
          <p v-else class="text-sm text-slate-400">Nenhum pedido pendente.</p>
        </div>
      </div>
    </div>

    <!-- Atividades -->
    <div class="rounded-xl border border-slate-200 bg-white p-5">
      <h2 class="mb-3 text-sm font-semibold text-slate-600">Atividades</h2>
      <form class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-6" @submit.prevent="register">
        <select v-model="form.kind" class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-1">
          <option v-for="k in activityKinds" :key="k.value" :value="k.value">{{ k.label }}</option>
        </select>
        <input v-model="form.channel" type="text" placeholder="Canal (ligação, visita…)"
               class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-2" />
        <input v-model="form.notes" type="text" placeholder="Observação"
               class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-2" />
        <button type="submit" :disabled="form.processing"
                class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50">
          Registrar
        </button>
      </form>

      <ul v-if="activities.length" class="divide-y divide-slate-100 text-sm">
        <li v-for="a in activities" :key="a.id" class="flex items-start justify-between gap-3 py-2">
          <div>
            <span class="rounded bg-slate-100 px-1.5 py-0.5 text-xs font-medium text-slate-600">{{ kindLabel(a.kind) }}</span>
            <span v-if="a.channel" class="ml-1 text-xs text-slate-400">{{ a.channel }}</span>
            <p class="mt-0.5 text-slate-600">{{ a.notes || '—' }}</p>
          </div>
          <div class="shrink-0 text-right text-xs text-slate-400">
            {{ fmtDateTime(a.occurred_at) }}<br />{{ a.user }}
          </div>
        </li>
      </ul>
      <p v-else class="text-sm text-slate-400">Nenhuma atividade registrada ainda.</p>
    </div>
  </div>
</template>
