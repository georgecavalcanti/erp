<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { useFloating, offset, flip, shift, size, autoUpdate } from '@floating-ui/vue'

interface Option {
  id: number
  name: string
}

const props = withDefaults(
  defineProps<{
    label: string
    options: Option[]
    modelValue: number[]
    searchable?: boolean
    allLabel?: string
  }>(),
  { searchable: false, allLabel: 'Todos' },
)

const emit = defineEmits<{ 'update:modelValue': [number[]] }>()

const open = ref(false)
const search = ref('')
const reference = ref<HTMLElement | null>(null)
const floating = ref<HTMLElement | null>(null)

// Popover flutuante: posição fixa (sobrepõe a tela, não empurra o layout),
// reposiciona ao rolar/redimensionar e limita a altura à viewport — o scroll
// fica dentro do próprio popover, não na página.
const { floatingStyles, isPositioned } = useFloating(reference, floating, {
  open,
  strategy: 'fixed',
  placement: 'bottom-start',
  whileElementsMounted: autoUpdate,
  middleware: [
    offset(4),
    flip({ padding: 8 }),
    shift({ padding: 8 }),
    size({
      padding: 8,
      apply({ availableHeight, rects, elements }) {
        Object.assign(elements.floating.style, {
          maxHeight: `${Math.max(180, availableHeight)}px`,
          minWidth: `${rects.reference.width}px`,
        })
      },
    }),
  ],
})

const selected = computed(() => new Set(props.modelValue))

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return props.options
  return props.options.filter((o) => o.name.toLowerCase().includes(q))
})

// Resumo no botão: "Todos" quando vazio, os nomes quando poucos, contagem quando muitos.
const summary = computed(() => {
  if (props.modelValue.length === 0) return props.allLabel
  const names = props.modelValue
    .map((id) => props.options.find((o) => o.id === id)?.name)
    .filter((n): n is string => Boolean(n))
  if (names.length <= 2) return names.join(', ')
  return `${names.length} selecionados`
})

function toggle(id: number) {
  const next = new Set(props.modelValue)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  emit('update:modelValue', [...next])
}

function selectAll() {
  emit(
    'update:modelValue',
    props.options.map((o) => o.id),
  )
}

function clear() {
  emit('update:modelValue', [])
}

function onDocMouseDown(e: MouseEvent) {
  if (!open.value) return
  const target = e.target as Node
  if (reference.value?.contains(target) || floating.value?.contains(target)) return
  open.value = false
}

onMounted(() => document.addEventListener('mousedown', onDocMouseDown))
onBeforeUnmount(() => document.removeEventListener('mousedown', onDocMouseDown))
</script>

<template>
  <div>
    <label class="mb-1 block text-xs font-medium text-slate-500">{{ label }}</label>
    <button
      ref="reference"
      type="button"
      class="flex w-full items-center justify-between rounded-md border border-slate-300 bg-white px-3 py-2 text-left text-sm shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
      @click="open = !open"
    >
      <span class="truncate" :class="modelValue.length ? 'text-slate-700' : 'text-slate-400'">{{ summary }}</span>
      <svg class="ml-2 h-4 w-4 shrink-0 text-slate-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.17l3.71-3.94a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
      </svg>
    </button>

    <Teleport to="body">
      <div
        v-if="open"
        ref="floating"
        :style="[floatingStyles, { visibility: isPositioned ? 'visible' : 'hidden' }]"
        class="z-50 flex max-w-[min(24rem,90vw)] flex-col overflow-hidden rounded-md border border-slate-200 bg-white shadow-lg"
      >
        <div v-if="searchable" class="shrink-0 border-b border-slate-100 p-2">
          <input
            v-model="search"
            type="text"
            placeholder="Buscar…"
            class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          />
        </div>
        <div class="min-h-0 flex-1 overflow-y-auto py-1">
          <label
            v-for="opt in filtered"
            :key="opt.id"
            class="flex cursor-pointer items-center gap-2 px-3 py-1.5 text-sm hover:bg-slate-50"
          >
            <input
              type="checkbox"
              :checked="selected.has(opt.id)"
              class="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
              @change="toggle(opt.id)"
            />
            <span class="truncate text-slate-700">{{ opt.name }}</span>
          </label>
          <p v-if="filtered.length === 0" class="px-3 py-4 text-center text-xs text-slate-400">Nada encontrado</p>
        </div>
        <div class="flex shrink-0 items-center justify-between border-t border-slate-100 px-3 py-2 text-xs">
          <button type="button" class="font-medium text-indigo-600 hover:text-indigo-500" @click="selectAll">
            Selecionar todos
          </button>
          <button type="button" class="font-medium text-slate-500 hover:text-slate-700" @click="clear">Limpar</button>
        </div>
      </div>
    </Teleport>
  </div>
</template>
