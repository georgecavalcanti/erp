<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { Link, usePage, usePoll, router } from '@inertiajs/vue3'
import FlashMessages from '@/components/FlashMessages.vue'

const page = usePage()
const user = computed(() => page.props.auth?.user ?? null)
const currentPath = computed(() => new URL(page.url, 'http://x').pathname)

// Auto-refresh: recarrega a tela atual a cada 30s reaproveitando a URL vigente
// (window.location.href) — logo, mantém os filtros da query string. O reload do
// Inertia já força preserveScroll/preserveState, então não pula o scroll nem
// atrapalha quem está ajustando um filtro. Com a aba em segundo plano, o Inertia
// reduz a frequência automaticamente.
const REFRESH_MS = 30_000
usePoll(REFRESH_MS)

const lastUpdate = ref(nowLabel())
function nowLabel() {
  return new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
}
let stopOnSuccess: (() => void) | undefined
onMounted(() => {
  stopOnSuccess = router.on('success', () => {
    lastUpdate.value = nowLabel()
  })
})
onUnmounted(() => stopOnSuccess?.())

const NAV = [
  { label: 'Visão geral', href: '/', exact: true },
  { label: 'Situação geral', href: '/situacao' },
  { label: 'Vendedores', href: '/vendedores' },
  { label: 'Parceiros', href: '/parceiros' },
  { label: 'Carteira', href: '/carteira' },
  { label: 'Inadimplência', href: '/inadimplencia' },
  { label: 'Devoluções', href: '/devolucoes' },
]

function isActive(item: { href: string; exact?: boolean }) {
  return item.exact ? currentPath.value === item.href : currentPath.value.startsWith(item.href)
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900">
    <div class="flex">
      <!-- Sidebar -->
      <aside class="fixed inset-y-0 left-0 hidden w-60 flex-col border-r border-slate-200 bg-white lg:flex">
        <div class="flex h-16 items-center gap-2 border-b border-slate-200 px-6">
          <div class="flex h-8 w-8 items-center justify-center rounded-lg bg-indigo-600 text-sm font-bold text-white">F</div>
          <span class="text-sm font-semibold text-slate-800">Faturamento</span>
        </div>
        <nav class="flex-1 space-y-1 p-3">
          <Link
            v-for="item in NAV"
            :key="item.href"
            :href="item.href"
            class="block rounded-lg px-3 py-2 text-sm font-medium transition"
            :class="isActive(item) ? 'bg-indigo-50 text-indigo-700' : 'text-slate-600 hover:bg-slate-100'"
          >
            {{ item.label }}
          </Link>
        </nav>
      </aside>

      <!-- Conteúdo -->
      <div class="flex-1 lg:pl-60">
        <header class="flex h-16 items-center justify-between border-b border-slate-200 bg-white px-6">
          <div class="lg:hidden">
            <span class="text-sm font-semibold text-slate-800">Faturamento</span>
          </div>
          <div class="ml-auto flex items-center gap-4">
            <span
              class="hidden items-center gap-1.5 text-xs text-slate-400 sm:inline-flex"
              title="A tela atualiza sozinha a cada 30s, mantendo os filtros aplicados"
            >
              <span class="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-500"></span>
              Atualizado às {{ lastUpdate }}
            </span>
            <span class="hidden text-sm text-slate-500 sm:inline">{{ user?.email }}</span>
            <Link
              href="/session"
              method="delete"
              as="button"
              class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              Sair
            </Link>
          </div>
        </header>

        <!-- Nav mobile -->
        <nav class="flex gap-1 overflow-x-auto border-b border-slate-200 bg-white px-4 py-2 lg:hidden">
          <Link
            v-for="item in NAV"
            :key="item.href"
            :href="item.href"
            class="whitespace-nowrap rounded-lg px-3 py-1.5 text-sm font-medium"
            :class="isActive(item) ? 'bg-indigo-50 text-indigo-700' : 'text-slate-600'"
          >
            {{ item.label }}
          </Link>
        </nav>

        <main class="p-6">
          <FlashMessages />
          <slot />
        </main>
      </div>
    </div>
  </div>
</template>
