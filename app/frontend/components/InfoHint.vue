<script setup lang="ts">
import { ref } from 'vue'
import { useFloating, offset, flip, shift, autoUpdate } from '@floating-ui/vue'
import type { FilterScope } from '@/types/models'

const props = withDefaults(
  defineProps<{
    text: string
    scope?: FilterScope
    scopeNote?: string
  }>(),
  { scope: 'all' },
)

const open = ref(false)
const reference = ref<HTMLElement | null>(null)
const floating = ref<HTMLElement | null>(null)

// Popover flutuante (fixed + Teleport): sobrepõe a tela sem empurrar/cortar nada,
// e reposiciona sozinho (flip/shift) para não sair da viewport.
const { floatingStyles } = useFloating(reference, floating, {
  open,
  placement: 'top',
  strategy: 'fixed',
  whileElementsMounted: autoUpdate,
  middleware: [offset(8), flip({ padding: 8 }), shift({ padding: 8 })],
})

const SCOPES: Record<FilterScope, { label: string; dot: string; text: string }> = {
  all: { label: 'Responde a todos os filtros', dot: 'bg-emerald-500', text: 'text-emerald-600' },
  partial: { label: 'Responde a alguns filtros', dot: 'bg-amber-500', text: 'text-amber-600' },
  none: { label: 'Não é afetado pelos filtros', dot: 'bg-slate-400', text: 'text-slate-500' },
}
</script>

<template>
  <span
    ref="reference"
    class="inline-flex cursor-help align-middle text-slate-300 outline-none transition-colors hover:text-indigo-500 focus-visible:text-indigo-500"
    tabindex="0"
    role="button"
    aria-label="Sobre este indicador"
    @mouseenter="open = true"
    @mouseleave="open = false"
    @focus="open = true"
    @blur="open = false"
  >
    <svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zM9 9a1 1 0 011-1h.008a1 1 0 01.992 1v3a1 1 0 11-2 0V9zm1-4.25a1.25 1.25 0 100 2.5 1.25 1.25 0 000-2.5z"
        clip-rule="evenodd"
      />
    </svg>
  </span>

  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 translate-y-1"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        ref="floating"
        :style="floatingStyles"
        class="pointer-events-none z-50 w-64 rounded-lg border border-slate-200 bg-white p-3 shadow-xl"
      >
        <p class="text-xs leading-relaxed text-slate-600">{{ text }}</p>
        <div class="mt-2 flex items-center gap-1.5 border-t border-slate-100 pt-2" :class="SCOPES[scope].text">
          <span class="h-1.5 w-1.5 shrink-0 rounded-full" :class="SCOPES[scope].dot"></span>
          <span class="text-[11px] font-medium">{{ scopeNote ?? SCOPES[scope].label }}</span>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
