<script setup lang="ts">
import InfoHint from '@/components/InfoHint.vue'
import type { FilterScope } from '@/types/models'

defineProps<{
  title: string
  subtitle?: string
  hint?: string
  hintScope?: FilterScope
  hintNote?: string
}>()
</script>

<template>
  <section class="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
    <header class="mb-4 flex items-baseline justify-between gap-3">
      <div>
        <h3 class="flex items-center gap-1.5 text-sm font-semibold text-slate-700">
          {{ title }}
          <InfoHint v-if="hint" :text="hint" :scope="hintScope" :scope-note="hintNote" />
        </h3>
        <p v-if="subtitle" class="text-xs text-slate-400">{{ subtitle }}</p>
      </div>
      <slot name="actions" />
    </header>
    <slot />
  </section>
</template>
