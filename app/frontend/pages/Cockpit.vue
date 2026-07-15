<script setup lang="ts">
import { computed } from 'vue'
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import KpiCard from '@/components/KpiCard.vue'
import { brl } from '@/lib/format'

defineOptions({ layout: AppLayout })

interface Component { key: string; label: string; value: number; weight?: number; base?: number }
interface Scenario { value: number; margin_value: number | null; confidence: number; gap: number | null; components: Component[] }
interface Projection {
  business_days: { total: number; elapsed: number; remaining: number }
  target: number | null
  realized: number
  realized_margin: number
  expected_to_date: number | null
  attainment_percent: number | null
  daily_rhythm_needed: number | null
  scenarios: { conservative: Scenario; likely: Scenario; potential: Scenario }
}

const props = defineProps<{
  salesperson: { id: number; name: string } | null
  month: string
  projection: Projection | null
}>()

const p = computed(() => props.projection)

// No ritmo esperado? Compara realizado com a meta proporcional aos dias decorridos.
const onTrack = computed(() => {
  const proj = p.value
  if (!proj || proj.expected_to_date == null) return null
  return proj.realized >= proj.expected_to_date
})

// Largura das barras (realizado e esperado) como % da meta, teto 100.
function pctOfTarget(value: number | null | undefined): number {
  const target = p.value?.target
  if (!target || !value) return 0
  return Math.min(100, Math.round((value / target) * 100))
}

const SCENARIOS = [
  { key: 'conservative', label: 'Conservador', tone: 'text-slate-700' },
  { key: 'likely', label: 'Provável', tone: 'text-indigo-700' },
  { key: 'potential', label: 'Potencial', tone: 'text-emerald-700' },
] as const

function scenario(key: 'conservative' | 'likely' | 'potential'): Scenario | null {
  return p.value?.scenarios[key] ?? null
}

const attainmentSub = computed(() => {
  const a = p.value?.attainment_percent
  return a == null ? 'sem meta definida' : `${a.toFixed(0)}% da meta`
})
</script>

<template>
  <Head title="Cockpit" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Cockpit</h1>
      <p class="text-sm text-slate-500">
        <span v-if="salesperson">{{ salesperson.name }} · </span>{{ month }}
      </p>
    </div>

    <!-- Vendedor sem vínculo com o ERP: não há carteira/projeção própria -->
    <div v-if="!salesperson || !p" class="rounded-xl border border-amber-200 bg-amber-50 p-6 text-sm text-amber-800">
      Este usuário ainda não está vinculado a um vendedor do ERP, então não há cockpit próprio.
      Peça ao administrador para vincular seu usuário a um vendedor.
    </div>

    <template v-else>
      <!-- KPIs -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Meta do mês" :value="p.target != null ? brl(p.target) : '—'"
                 :sub="`${p.business_days.total} dias úteis`" />
        <KpiCard label="Realizado" :value="brl(p.realized)" :sub="attainmentSub"
                 :tone="onTrack === false ? 'warning' : 'positive'" />
        <KpiCard label="Esperado até hoje" :value="p.expected_to_date != null ? brl(p.expected_to_date) : '—'"
                 :sub="`${p.business_days.elapsed}/${p.business_days.total} dias úteis`"
                 :tone="onTrack === false ? 'negative' : 'default'" />
        <KpiCard label="Ritmo diário p/ meta" :value="p.daily_rhythm_needed != null ? brl(p.daily_rhythm_needed) : '—'"
                 :sub="`${p.business_days.remaining} dias úteis restantes`" tone="warning" />
      </div>

      <!-- Barra realizado vs esperado vs meta -->
      <div v-if="p.target" class="rounded-xl border border-slate-200 bg-white p-5">
        <div class="mb-2 flex items-center justify-between text-sm">
          <span class="font-medium text-slate-600">Progresso da meta</span>
          <span :class="onTrack ? 'text-emerald-600' : 'text-amber-600'">
            {{ onTrack ? 'No ritmo esperado' : 'Abaixo do esperado' }}
          </span>
        </div>
        <div class="relative h-4 w-full overflow-hidden rounded-full bg-slate-100">
          <div class="h-full rounded-full bg-indigo-500 transition-all" :style="{ width: pctOfTarget(p.realized) + '%' }"></div>
          <!-- marcador do esperado até hoje -->
          <div v-if="p.expected_to_date" class="absolute top-0 h-full w-0.5 bg-slate-500"
               :style="{ left: pctOfTarget(p.expected_to_date) + '%' }" title="Esperado até hoje"></div>
        </div>
        <div class="mt-1 flex justify-between text-xs text-slate-400">
          <span>{{ brl(p.realized) }} realizado</span>
          <span>meta {{ brl(p.target) }}</span>
        </div>
      </div>

      <!-- Cenários de projeção -->
      <div>
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">Projeção de fechamento</h2>
        <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <div v-for="s in SCENARIOS" :key="s.key" class="rounded-xl border border-slate-200 bg-white p-5">
            <div class="flex items-center justify-between">
              <span class="text-sm font-medium text-slate-500">{{ s.label }}</span>
              <span class="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-500">
                {{ scenario(s.key)!.confidence }}% conf.
              </span>
            </div>
            <p class="mt-2 text-2xl font-semibold tabular-nums" :class="s.tone">{{ brl(scenario(s.key)!.value) }}</p>
            <p v-if="scenario(s.key)!.gap != null" class="mt-1 text-xs"
               :class="scenario(s.key)!.gap! > 0 ? 'text-amber-600' : 'text-emerald-600'">
              {{ scenario(s.key)!.gap! > 0 ? `Gap ${brl(scenario(s.key)!.gap!)}` : 'Meta superada' }}
            </p>

            <!-- Parcelas rastreáveis (explicabilidade, MVP 5) -->
            <ul class="mt-4 space-y-1 border-t border-slate-100 pt-3 text-xs text-slate-500">
              <li v-for="c in scenario(s.key)!.components" :key="c.key" class="flex justify-between gap-2">
                <span class="truncate">
                  {{ c.label }}<span v-if="c.weight != null" class="text-slate-400"> · {{ Math.round(c.weight * 100) }}%</span>
                </span>
                <span class="tabular-nums text-slate-600">{{ brl(c.value) }}</span>
              </li>
            </ul>
          </div>
        </div>
        <p class="mt-3 text-xs text-slate-400">
          Projeção determinística (realizado + carteira ponderada + ritmo dos dias restantes). Recompra, cotação e
          cross-sell entram como novas parcelas nas próximas fases.
        </p>
      </div>
    </template>
  </div>
</template>
