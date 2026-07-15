<script setup lang="ts">
import { ref } from 'vue'
import { Head, router, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import Pagination from '@/components/Pagination.vue'
import type { Pagination as PaginationType } from '@/types/models'

defineOptions({ layout: AppLayout })

interface Option { id: number; name: string }
interface RespOption { value: string; label: string }
interface WalletRow {
  id: number
  partner: string
  partner_external_code: number
  city: string | null
  state: string | null
  salesperson: string
  responsibility: string
  region: string | null
  starts_on: string | null
}

const props = defineProps<{
  wallets: WalletRow[]
  pagination: PaginationType
  filters: { salesperson_id: number | null }
  options: { salespeople: Option[]; responsibilities: RespOption[] }
  summary: { total_active: number; sellers: number }
}>()

const selectedSeller = ref<number | null>(props.filters.salesperson_id)

function filterBySeller() {
  router.get('/admin/carteiras', { salesperson_id: selectedSeller.value || undefined }, { preserveState: true })
}

const form = useForm({
  partner_external_code: '',
  salesperson_id: props.filters.salesperson_id ?? null,
  responsibility_type: 'owner',
  region: '',
})

function assign() {
  form.post('/admin/carteiras', { onSuccess: () => form.reset('partner_external_code', 'region') })
}

function remove(w: WalletRow) {
  if (confirm(`Remover ${w.partner} da carteira de ${w.salesperson}?`)) {
    router.delete(`/admin/carteiras/${w.id}`)
  }
}
</script>

<template>
  <Head title="Carteiras" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Carteiras</h1>
      <p class="text-sm text-slate-500">
        {{ summary.total_active }} vínculos vigentes · {{ summary.sellers }} vendedores com carteira
      </p>
    </div>

    <!-- Atribuir / transferir cliente -->
    <form class="grid grid-cols-1 gap-3 rounded-lg border border-slate-200 bg-white p-4 sm:grid-cols-5" @submit.prevent="assign">
      <div class="sm:col-span-1">
        <label class="mb-1 block text-xs font-medium text-slate-500">CODPARC do cliente</label>
        <input v-model="form.partner_external_code" type="text" required placeholder="ex.: 4242"
               class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500" />
      </div>
      <div class="sm:col-span-2">
        <label class="mb-1 block text-xs font-medium text-slate-500">Vendedor</label>
        <select v-model="form.salesperson_id" required
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500">
          <option :value="null">— selecione —</option>
          <option v-for="s in options.salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs font-medium text-slate-500">Responsabilidade</label>
        <select v-model="form.responsibility_type"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500">
          <option v-for="r in options.responsibilities" :key="r.value" :value="r.value">{{ r.label }}</option>
        </select>
      </div>
      <div class="flex items-end">
        <button type="submit" :disabled="form.processing"
                class="w-full rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50">
          Atribuir
        </button>
      </div>
      <p class="text-xs text-slate-400 sm:col-span-5">
        Se o cliente já tiver dono, a carteira vigente é encerrada e transferida para o vendedor escolhido (registra autor e data).
      </p>
    </form>

    <!-- Filtro por vendedor -->
    <div class="flex items-center gap-2">
      <label class="text-sm text-slate-500">Ver carteira de:</label>
      <select v-model="selectedSeller" class="rounded-md border-slate-300 text-sm shadow-sm" @change="filterBySeller">
        <option :value="null">Todos os vendedores</option>
        <option v-for="s in options.salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
    </div>

    <div class="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
          <tr>
            <th class="px-4 py-3">Cliente</th>
            <th class="px-4 py-3">Local</th>
            <th class="px-4 py-3">Vendedor</th>
            <th class="px-4 py-3">Responsabilidade</th>
            <th class="px-4 py-3">Desde</th>
            <th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="w in wallets" :key="w.id" class="hover:bg-slate-50">
            <td class="px-4 py-3 font-medium text-slate-700">
              {{ w.partner }}
              <span class="text-xs text-slate-400">#{{ w.partner_external_code }}</span>
            </td>
            <td class="px-4 py-3 text-slate-600">{{ [w.city, w.state].filter(Boolean).join(' / ') || '—' }}</td>
            <td class="px-4 py-3 text-slate-600">{{ w.salesperson }}</td>
            <td class="px-4 py-3 text-slate-600 capitalize">{{ w.responsibility }}</td>
            <td class="px-4 py-3 text-slate-500">{{ w.starts_on || '—' }}</td>
            <td class="px-4 py-3 text-right">
              <button class="text-sm font-medium text-red-600 hover:underline" @click="remove(w)">Remover</button>
            </td>
          </tr>
          <tr v-if="wallets.length === 0">
            <td colspan="6" class="px-4 py-8 text-center text-slate-400">Nenhuma carteira para este filtro.</td>
          </tr>
        </tbody>
      </table>
    </div>

    <Pagination v-if="pagination.pages > 1" :pagination="pagination" />
  </div>
</template>
