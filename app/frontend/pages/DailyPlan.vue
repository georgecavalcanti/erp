<script setup lang="ts">
import { computed, ref } from 'vue'
import { Head, Link, router, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import { brl } from '@/lib/format'

defineOptions({ layout: AppLayout })

interface Tag { key: string; label: string }
interface Rec {
  id: number
  partner_id: number
  partner: string | null
  position: number | null
  score: number | null
  diagnosis: string | null
  next_action: string | null
  channel: string | null
  potential: number
  confidence: number | null
  reasons: Tag[]
  restrictions: Tag[]
  status: string
  influenced: number
  approach: string | null
}
interface Origin { count: number; expected: number }

const props = defineProps<{
  salesperson: { id: number; name: string } | null
  capacity: number | null
  channels: string[]
  recommendations: Rec[]
  simulator: { gap: number | null; projected: number; covers_gap: boolean; count: number; by_origin: Record<string, Origin> } | null
  salespeople: { id: number; name: string }[] | null
  agentEnabled: boolean
}>()

// Abordagens geradas pelo Claude (Sprint 8): uma execução para os cards
// pendentes sem abordagem.
const generatingApproaches = ref(false)
const missingApproaches = computed(() =>
  props.recommendations.some((r) => r.status === 'pending' && !r.approach))
function generateApproaches() {
  generatingApproaches.value = true
  router.post('/plano-do-dia/abordagens', { salesperson_id: props.salesperson?.id },
    { preserveScroll: true, onFinish: () => (generatingApproaches.value = false) })
}

const RESTR_TONE = 'text-red-700 bg-red-50 ring-red-200'
const REASON_TONE: Record<string, string> = {
  recompra_atrasada: 'text-amber-700 bg-amber-50 ring-amber-200',
  queda_consumo: 'text-amber-700 bg-amber-50 ring-amber-200',
  inadimplencia: 'text-red-700 bg-red-50 ring-red-200',
  risco: 'text-red-700 bg-red-50 ring-red-200',
  sem_contato: 'text-slate-600 bg-slate-100 ring-slate-200',
}
const STATUS_LABEL: Record<string, string> = {
  pending: 'Pendente', accepted: 'Aceita', postponed: 'Adiada', done: 'Concluída',
}

function act(rec: Rec, event: string) {
  router.patch(`/recomendacoes/${rec.id}`, { event }, { preserveScroll: true })
}
function switchSeller(e: Event) {
  router.get('/plano-do-dia', { salesperson_id: (e.target as HTMLSelectElement).value }, { preserveState: false })
}

// Formulário de resultado (inline por recomendação)
const resultFor = ref<number | null>(null)
const form = useForm({ amount: '', invoice_uid: '', notes: '' })
function openResult(rec: Rec) {
  resultFor.value = resultFor.value === rec.id ? null : rec.id
  form.reset()
}
function submitResult(rec: Rec) {
  form.post(`/recomendacoes/${rec.id}/resultado`, { preserveScroll: true, onSuccess: () => (resultFor.value = null) })
}
</script>

<template>
  <Head title="Plano do dia" />
  <div class="space-y-6">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold text-slate-800">Plano do dia</h1>
        <p class="text-sm text-slate-500">
          <template v-if="salesperson">{{ recommendations.length }} ações priorizadas · capacidade {{ capacity }}/dia</template>
          <template v-else>Sem carteira vinculada.</template>
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button v-if="agentEnabled && salesperson && missingApproaches" :disabled="generatingApproaches"
                class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50 disabled:opacity-50"
                @click="generateApproaches">
          {{ generatingApproaches ? 'Gerando abordagens…' : 'Gerar abordagens (Claude)' }}
        </button>
        <select v-if="salespeople" class="rounded-md border-slate-300 text-sm shadow-sm" :value="salesperson?.id" @change="switchSeller">
          <option v-for="s in salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
      </div>
    </div>

    <!-- Simulador de meta -->
    <div v-if="simulator && simulator.gap != null" class="rounded-xl border border-slate-200 bg-white p-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-sm font-semibold text-slate-600">Simulador de meta</h2>
          <p class="text-sm text-slate-500">
            Gap de <span class="font-semibold text-slate-700">{{ brl(simulator.gap) }}</span> ·
            plano projeta <span class="font-semibold" :class="simulator.covers_gap ? 'text-emerald-600' : 'text-amber-600'">{{ brl(simulator.projected) }}</span>
            em {{ simulator.count }} ações
          </p>
        </div>
        <span class="rounded-full px-3 py-1 text-sm font-medium" :class="simulator.covers_gap ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700'">
          {{ simulator.covers_gap ? 'Cobre a meta' : 'Ainda falta' }}
        </span>
      </div>
      <div class="mt-3 flex flex-wrap gap-2 text-xs">
        <span v-for="(o, key) in simulator.by_origin" :key="key" class="rounded bg-slate-100 px-2 py-1 text-slate-600">
          {{ key }}: {{ o.count }} · {{ brl(o.expected) }}
        </span>
      </div>
    </div>

    <!-- Lista de recomendações -->
    <div class="space-y-3">
      <div v-for="rec in recommendations" :key="rec.id" class="rounded-xl border border-slate-200 bg-white p-4"
           :class="rec.status === 'done' ? 'opacity-60' : ''">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-slate-800 text-xs font-semibold text-white">{{ rec.position ?? '·' }}</span>
              <Link :href="`/clientes/${rec.partner_id}`" class="truncate font-medium text-slate-800 hover:underline">{{ rec.partner }}</Link>
              <span v-if="rec.status !== 'pending'" class="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">{{ STATUS_LABEL[rec.status] ?? rec.status }}</span>
            </div>
            <p class="mt-1 text-sm text-slate-600">{{ rec.next_action }}</p>
            <p v-if="rec.diagnosis" class="text-xs text-slate-400">{{ rec.diagnosis }}</p>
            <div class="mt-2 flex flex-wrap gap-1">
              <span v-for="r in rec.reasons" :key="r.key" class="rounded px-1.5 py-0.5 text-xs font-medium ring-1" :class="REASON_TONE[r.key] ?? 'text-slate-600 bg-slate-100 ring-slate-200'">{{ r.label }}</span>
              <span v-for="r in rec.restrictions" :key="r.key" class="rounded px-1.5 py-0.5 text-xs font-medium ring-1" :class="RESTR_TONE">⚠ {{ r.label }}</span>
            </div>
            <!-- Abordagem redigida pelo agente (Sprint 8) -->
            <p v-if="rec.approach" class="mt-2 rounded-lg bg-indigo-50/60 px-3 py-2 text-sm text-slate-700">
              <span class="font-medium text-indigo-700">Abordagem:</span> {{ rec.approach }}
            </p>
          </div>
          <div class="shrink-0 text-right">
            <div class="tabular-nums font-semibold text-slate-800">{{ brl(rec.potential) }}</div>
            <div class="text-xs text-slate-400">{{ rec.confidence }}% conv · score {{ rec.score }}</div>
            <div v-if="rec.influenced > 0" class="text-xs font-medium text-emerald-600">+{{ brl(rec.influenced) }} influenciado</div>
          </div>
        </div>

        <!-- Ações -->
        <div v-if="rec.status !== 'done'" class="mt-3 flex flex-wrap gap-2 border-t border-slate-100 pt-3 text-sm">
          <button class="rounded-md bg-emerald-600 px-3 py-1.5 font-medium text-white hover:bg-emerald-700" @click="openResult(rec)">Registrar resultado</button>
          <button class="rounded-md border border-slate-300 px-3 py-1.5 text-slate-600 hover:bg-slate-50" @click="act(rec, 'concluir')">Concluir</button>
          <button class="rounded-md border border-slate-300 px-3 py-1.5 text-slate-600 hover:bg-slate-50" @click="act(rec, 'adiar')">Adiar</button>
          <button class="rounded-md border border-slate-300 px-3 py-1.5 text-slate-400 hover:bg-slate-50" @click="act(rec, 'descartar')">Descartar</button>
        </div>

        <!-- Formulário de resultado -->
        <form v-if="resultFor === rec.id" class="mt-3 grid grid-cols-1 gap-2 rounded-lg bg-slate-50 p-3 sm:grid-cols-4" @submit.prevent="submitResult(rec)">
          <input v-model="form.amount" type="number" step="0.01" placeholder="Valor influenciado (R$)" class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-1" />
          <input v-model="form.invoice_uid" type="text" placeholder="Nº da nota (opcional)" class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-1" />
          <input v-model="form.notes" type="text" placeholder="Observação" class="rounded-md border-slate-300 text-sm shadow-sm sm:col-span-1" />
          <button type="submit" :disabled="form.processing" class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50">Salvar resultado</button>
        </form>
      </div>

      <div v-if="recommendations.length === 0 && salesperson" class="rounded-xl border border-dashed border-slate-200 p-8 text-center text-slate-400">
        Nenhuma ação no plano de hoje.
      </div>
    </div>
  </div>
</template>
