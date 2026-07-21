<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { Head, Link, router } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import { brl } from '@/lib/format'

defineOptions({ layout: AppLayout })

interface Card {
  id: number
  partner_id: number | null
  partner: string | null
  diagnosis: string | null
  recommendation: string | null
  evidences: string[]
  impact: Record<string, number | string>
  confidence: number | null
  next_action: string | null
  channel: string | null
  deadline: string | null
  restrictions: string[]
  status: string
}
interface Answer {
  resumo: string | null
  recomendacoes: Card[]
  dados_ausentes: string[]
  degraded?: boolean
  aviso?: string | null
  generated_at: string | null
}
interface Turn { role: 'user' | 'assistant'; content: string; answer?: Answer }

const props = defineProps<{
  salesperson: { id: number; name: string } | null
  salespeople: { id: number; name: string }[] | null
  agentEnabled: boolean
  suggestions: string[]
  lastResponse: Answer | null
}>()

const turns = ref<Turn[]>([])
const question = ref('')
const busy = ref(false)
const statusLine = ref<string | null>(null)
const chatEl = ref<HTMLElement | null>(null)

// Rótulos amigáveis para o progresso das ferramentas no stream.
const TOOL_LABELS: Record<string, string> = {
  consultar_meta: 'Consultando sua meta',
  consultar_resultado_vendedor: 'Verificando seu resultado',
  consultar_cliente_360: 'Abrindo o Cliente 360',
  consultar_vendas_cliente: 'Lendo o histórico de vendas',
  consultar_pedidos_abertos: 'Conferindo pedidos abertos',
  consultar_estoque: 'Consultando estoque',
  consultar_precos: 'Consultando preços',
  consultar_credito: 'Verificando crédito',
  consultar_interacoes: 'Revendo as últimas interações',
  calcular_projecao: 'Analisando sua projeção',
  prever_recompra: 'Analisando recompras',
  detectar_clientes_em_risco: 'Varrendo clientes em risco',
  detectar_queda_de_consumo: 'Procurando quedas de consumo',
  identificar_cross_sell: 'Buscando cross-sell',
  calcular_potencial_cliente: 'Calculando potencial do cliente',
  priorizar_carteira: 'Priorizando sua carteira',
  simular_plano_para_meta: 'Simulando plano para a meta',
}

const CHANNEL_LABELS: Record<string, string> = {
  call: 'Ligação', whatsapp: 'WhatsApp', visit: 'Visita', email: 'E-mail', internal: 'Interno',
}
const STATUS_LABEL: Record<string, string> = {
  pending: 'Pendente', accepted: 'Aceita', postponed: 'Adiada', discarded: 'Descartada', done: 'Concluída',
}

const showWelcome = computed(() => turns.value.length === 0)

function scrollToEnd() {
  nextTick(() => chatEl.value?.scrollTo({ top: chatEl.value.scrollHeight, behavior: 'smooth' }))
}

function csrfToken(): string {
  const m = document.cookie.match(/(?:^|;\s*)CSRF-TOKEN=([^;]+)/)
  return m ? decodeURIComponent(m[1]) : ''
}

async function ask(text?: string) {
  const q = (text ?? question.value).trim()
  if (!q || busy.value) return
  question.value = ''
  busy.value = true
  statusLine.value = 'Pensando…'

  // Histórico curto (últimos turnos) para continuidade da conversa.
  const history = turns.value.slice(-6).map((t) => ({ role: t.role, content: t.content }))
  turns.value.push({ role: 'user', content: q })
  scrollToEnd()

  try {
    const res = await fetch('/copiloto/perguntar', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken(), Accept: 'text/event-stream' },
      body: JSON.stringify({ question: q, history, salesperson_id: props.salesperson?.id }),
    })
    if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)
    const gotFinal = await consumeStream(res.body)
    // Stream fechou sem result/error (ex.: servidor caiu no meio): a pergunta
    // não pode terminar em silêncio — mostra falha explícita.
    if (!gotFinal) throw new Error('stream sem resultado')
  } catch {
    turns.value.push({
      role: 'assistant', content: '',
      answer: { resumo: null, recomendacoes: [], dados_ausentes: [], degraded: true, aviso: 'Falha de comunicação com o copiloto — tente de novo.', generated_at: null },
    })
  } finally {
    busy.value = false
    statusLine.value = null
    scrollToEnd()
  }
}

// Parser SSE sobre fetch (EventSource não faz POST): acumula o buffer e
// despacha cada bloco "event:/data:" completo. Devolve se um evento FINAL
// (result/error) chegou — stream que fecha sem final é falha, não sucesso.
async function consumeStream(body: ReadableStream<Uint8Array>): Promise<boolean> {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let gotFinal = false
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    let idx: number
    while ((idx = buffer.indexOf('\n\n')) >= 0) {
      gotFinal = dispatch(buffer.slice(0, idx)) || gotFinal
      buffer = buffer.slice(idx + 2)
    }
  }
  return gotFinal
}

// Devolve true quando o bloco é um evento final (result/error).
function dispatch(block: string): boolean {
  const event = /^event: (.+)$/m.exec(block)?.[1]
  const data = /^data: (.+)$/m.exec(block)?.[1]
  if (!event || !data) return false
  const payload = JSON.parse(data)

  if (event === 'status') {
    statusLine.value = payload.type === 'tool'
      ? `${TOOL_LABELS[payload.tool] ?? payload.tool}…`
      : 'Pensando…'
    return false
  } else if (event === 'result') {
    turns.value.push({ role: 'assistant', content: payload.resumo ?? '', answer: payload as Answer })
    return true
  } else if (event === 'error') {
    turns.value.push({
      role: 'assistant', content: '',
      answer: { resumo: null, recomendacoes: [], dados_ausentes: [], degraded: true, aviso: payload.message, generated_at: null },
    })
    return true
  }
  return false
}

// Ações dos cards: mesmo endpoint da Sprint 7, mas via fetch — o router do
// Inertia seguiria o redirect do controller para o Plano do Dia e DESTRUIRIA a
// conversa (revisão cruzada Sprint 8). Atualiza o status local no sucesso.
async function act(card: Card, event: string, newStatus: string) {
  try {
    const res = await fetch(`/recomendacoes/${card.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ event }),
    })
    if (res.ok) card.status = newStatus
  } catch {
    /* falha de rede: mantém o status atual — o usuário tenta de novo */
  }
}

function switchSeller(e: Event) {
  router.get('/copiloto', { salesperson_id: (e.target as HTMLSelectElement).value }, { preserveState: false })
}

function fmtWhen(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  return `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}
</script>

<template>
  <Head title="Copiloto" />
  <div class="flex h-[calc(100vh-8rem)] flex-col space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 class="text-xl font-semibold text-slate-800">Copiloto</h1>
        <p class="text-sm text-slate-500">
          <template v-if="salesperson">Carteira de {{ salesperson.name }} · só ferramentas autorizadas, nada é enviado ao ERP</template>
          <template v-else>Sem carteira vinculada — o copiloto precisa de um vendedor com carteira.</template>
        </p>
      </div>
      <select v-if="salespeople" class="rounded-md border-slate-300 text-sm shadow-sm" :value="salesperson?.id" @change="switchSeller">
        <option v-for="s in salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
    </div>

    <!-- IA indisponível: aviso + última resposta válida (resiliência, doc 06) -->
    <div v-if="!agentEnabled" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
      <p class="font-medium">IA indisponível no momento.</p>
      <p>Os painéis e planos continuam funcionando normalmente. Abaixo, sua última resposta válida.</p>
    </div>

    <!-- Conversa -->
    <div ref="chatEl" class="flex-1 space-y-4 overflow-y-auto rounded-xl border border-slate-200 bg-white p-4">
      <!-- Boas-vindas + sugestões (5 casos de uso do doc 06) -->
      <div v-if="showWelcome" class="space-y-3 py-6 text-center">
        <p class="text-slate-500">Pergunte sobre sua meta, carteira, clientes ou peça um plano.</p>
        <div class="mx-auto flex max-w-2xl flex-wrap justify-center gap-2">
          <button v-for="s in suggestions" :key="s" :disabled="busy || !agentEnabled"
                  class="rounded-full border border-slate-300 px-3 py-1.5 text-sm text-slate-600 hover:bg-slate-50 disabled:opacity-50"
                  @click="ask(s)">{{ s }}</button>
        </div>
        <!-- Última resposta válida quando degradado -->
        <div v-if="lastResponse && !agentEnabled" class="mx-auto max-w-2xl rounded-lg bg-slate-50 p-4 text-left">
          <p class="mb-1 text-xs text-slate-400">Última resposta válida · {{ fmtWhen(lastResponse.generated_at) }}</p>
          <p class="whitespace-pre-wrap text-sm text-slate-700">{{ lastResponse.resumo }}</p>
        </div>
      </div>

      <template v-for="(turn, i) in turns" :key="i">
        <!-- Pergunta -->
        <div v-if="turn.role === 'user'" class="flex justify-end">
          <div class="max-w-[85%] rounded-2xl rounded-br-sm bg-slate-800 px-4 py-2 text-sm text-white">{{ turn.content }}</div>
        </div>

        <!-- Resposta -->
        <div v-else class="space-y-3">
          <div v-if="turn.answer?.degraded" class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-2 text-sm text-amber-800">
            ⚠ {{ turn.answer.aviso }}
            <span v-if="turn.answer.generated_at" class="text-amber-600"> · resposta de {{ fmtWhen(turn.answer.generated_at) }}</span>
          </div>
          <div v-if="turn.answer?.resumo" class="max-w-[92%] whitespace-pre-wrap rounded-2xl rounded-bl-sm bg-slate-100 px-4 py-3 text-sm text-slate-800">{{ turn.answer.resumo }}</div>

          <!-- Cards de recomendação -->
          <div v-for="card in turn.answer?.recomendacoes ?? []" :key="card.id"
               class="rounded-xl border border-slate-200 p-4" :class="card.status === 'discarded' ? 'opacity-50' : ''">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div class="min-w-0">
                <Link v-if="card.partner_id" :href="`/clientes/${card.partner_id}`" class="font-medium text-slate-800 hover:underline">{{ card.partner }}</Link>
                <span v-else class="font-medium text-slate-800">Recomendação</span>
                <span v-if="card.status !== 'pending'" class="ml-2 rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">{{ STATUS_LABEL[card.status] ?? card.status }}</span>
                <p class="mt-1 text-sm font-medium text-slate-700">{{ card.recommendation }}</p>
                <p class="text-xs text-slate-500">{{ card.diagnosis }}</p>
              </div>
              <div class="shrink-0 text-right text-xs text-slate-400">
                <div v-if="typeof card.impact?.receita === 'number'" class="tabular-nums text-sm font-semibold text-slate-700">{{ brl(card.impact.receita as number) }}</div>
                <div>{{ card.confidence }}% confiança</div>
                <div v-if="card.deadline">até {{ card.deadline }}</div>
              </div>
            </div>

            <p class="mt-2 text-sm text-slate-600"><span class="font-medium">Próxima ação:</span> {{ card.next_action }}
              <span v-if="card.channel" class="text-slate-400">· {{ CHANNEL_LABELS[card.channel] ?? card.channel }}</span></p>

            <div v-if="card.evidences.length || card.restrictions.length" class="mt-2 flex flex-wrap gap-1">
              <span v-for="e in card.evidences" :key="e" class="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">{{ e }}</span>
              <span v-for="r in card.restrictions" :key="r" class="rounded bg-red-50 px-1.5 py-0.5 text-xs font-medium text-red-700 ring-1 ring-red-200">⚠ {{ r }}</span>
            </div>

            <div v-if="card.status === 'pending'" class="mt-3 flex flex-wrap gap-2 border-t border-slate-100 pt-3 text-sm">
              <button class="rounded-md bg-emerald-600 px-3 py-1.5 font-medium text-white hover:bg-emerald-700" @click="act(card, 'aceitar', 'accepted')">Aceitar</button>
              <button class="rounded-md border border-slate-300 px-3 py-1.5 text-slate-600 hover:bg-slate-50" @click="act(card, 'adiar', 'postponed')">Adiar</button>
              <button class="rounded-md border border-slate-300 px-3 py-1.5 text-slate-400 hover:bg-slate-50" @click="act(card, 'descartar', 'discarded')">Descartar</button>
            </div>
          </div>

          <!-- Limitações declaradas (não inventa, doc 06) -->
          <div v-if="turn.answer?.dados_ausentes?.length" class="rounded-lg bg-slate-50 px-4 py-2 text-xs text-slate-500">
            <span class="font-medium">Dados ausentes:</span> {{ turn.answer.dados_ausentes.join(' · ') }}
          </div>
        </div>
      </template>

      <!-- Progresso do stream -->
      <div v-if="busy" class="flex items-center gap-2 text-sm text-slate-400">
        <span class="inline-block h-2 w-2 animate-pulse rounded-full bg-red-500"></span>
        {{ statusLine }}
      </div>
    </div>

    <!-- Entrada -->
    <form class="flex gap-2" @submit.prevent="ask()">
      <input v-model="question" type="text" :disabled="busy || !agentEnabled || !salesperson"
             placeholder="Pergunte ao copiloto…"
             class="flex-1 rounded-xl border-slate-300 shadow-sm focus:border-red-500 focus:ring-red-500 disabled:bg-slate-50" />
      <button type="submit" :disabled="busy || !agentEnabled || !salesperson || !question.trim()"
              class="rounded-xl bg-red-600 px-5 py-2 font-semibold text-white hover:bg-red-700 disabled:opacity-50">
        Enviar
      </button>
    </form>
  </div>
</template>
