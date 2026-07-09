<script setup lang="ts">
import InfoHint from '@/components/InfoHint.vue'
import type { FilterScope } from '@/types/models'

withDefaults(
  defineProps<{
    label: string
    value: string
    sub?: string
    tone?: 'default' | 'positive' | 'negative' | 'warning'
    hint?: string
    hintScope?: FilterScope
    hintNote?: string
  }>(),
  { tone: 'default' },
)

const TONES = {
  default: 'text-slate-900',
  positive: 'text-emerald-600',
  negative: 'text-red-600',
  warning: 'text-amber-600',
}
</script>

<template>
  <div class="min-w-0 rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
    <div class="flex items-center justify-between gap-2">
      <p class="truncate text-sm font-medium text-slate-500">{{ label }}</p>
      <InfoHint v-if="hint" :text="hint" :scope="hintScope" :scope-note="hintNote" class="shrink-0" />
    </div>
    <p class="mt-2 text-xl font-semibold leading-tight tabular-nums" :class="TONES[tone]">{{ value }}</p>
    <p v-if="sub" class="mt-1 text-xs text-slate-400">{{ sub }}</p>
  </div>
</template>
