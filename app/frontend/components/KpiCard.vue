<script setup lang="ts">
withDefaults(
  defineProps<{
    label: string
    value: string
    sub?: string
    tone?: 'default' | 'positive' | 'negative' | 'warning'
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
    <p class="truncate text-sm font-medium text-slate-500">{{ label }}</p>
    <p class="mt-2 text-xl font-semibold leading-tight tabular-nums" :class="TONES[tone]">{{ value }}</p>
    <p v-if="sub" class="mt-1 text-xs text-slate-400">{{ sub }}</p>
  </div>
</template>
