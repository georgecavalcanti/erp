<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { Link, usePage, usePoll, router } from '@inertiajs/vue3'
import FlashMessages from '@/components/FlashMessages.vue'
import jattoMark from '@/assets/jatto-mark.png'

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

// Último sync do Sankhya (shared prop). Atualiza sozinho junto com o auto-refresh,
// que repuxa as shared props a cada 30s.
const lastSync = computed(() => page.props.lastSync ?? null)
const syncLabel = computed(() => {
  const at = lastSync.value?.at
  if (!at) return null
  const d = new Date(at)
  const sameDay = d.toDateString() === new Date().toDateString()
  const hm = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
  return sameDay ? hm : `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${hm}`
})
const syncTitle = computed(() => {
  if (!lastSync.value) return 'Nenhuma sincronização com o Sankhya registrada ainda (roda a cada 30 min em horário comercial).'
  return lastSync.value.status === 'partial'
    ? 'A última sincronização com o Sankhya teve falhas parciais — alguns dados podem estar defasados.'
    : 'Última sincronização com o Sankhya (roda a cada 30 min em horário comercial).'
})

const NAV_REST = [
  { label: 'Situação geral', href: '/situacao' },
  { label: 'Vendedores', href: '/vendedores' },
  { label: 'Parceiros', href: '/parceiros' },
  { label: 'Carteira', href: '/carteira' },
  { label: 'Inadimplência', href: '/inadimplencia' },
  { label: 'Devoluções', href: '/devolucoes' },
]

// Home por perfil (doc 08): vendedor/representante têm o Cockpit como início;
// gestão/diretoria começam na visão geral consolidada.
const nav = computed(() => {
  const u = user.value as { role?: string } | null
  const seller = u?.role === 'vendedor' || u?.role === 'representante'
  if (seller) {
    return [
      { label: 'Cockpit', href: '/cockpit', exact: true },
      { label: 'Plano do dia', href: '/plano-do-dia' },
      { label: 'Minha carteira', href: '/minha-carteira' },
      ...NAV_REST,
    ]
  }
  // Gestão/diretoria também abrem o Plano do Dia (de um vendedor autorizado).
  return [{ label: 'Visão geral', href: '/', exact: true }, { label: 'Plano do dia', href: '/plano-do-dia' }, ...NAV_REST]
})

// Navegação de administração por perfil (doc 07): gestor/admin gerem carteiras e
// metas; só o admin gere usuários. As flags vêm do inertia_share.
const adminNav = computed(() => {
  const u = user.value as { isAdmin?: boolean; managesCommercial?: boolean } | null
  if (!u) return [] as { label: string; href: string }[]
  const items: { label: string; href: string }[] = []
  if (u.managesCommercial) {
    items.push({ label: 'Carteiras', href: '/admin/carteiras' })
    items.push({ label: 'Metas', href: '/admin/metas' })
    items.push({ label: 'Priorização', href: '/admin/priorizacao' })
  }
  if (u.isAdmin) items.push({ label: 'Usuários', href: '/admin/usuarios' })
  return items
})

function isActive(item: { href: string; exact?: boolean }) {
  return item.exact ? currentPath.value === item.href : currentPath.value.startsWith(item.href)
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900">
    <div class="flex">
      <!-- Sidebar -->
      <aside class="fixed inset-y-0 left-0 hidden w-60 flex-col border-r border-slate-200 bg-white lg:flex">
        <div class="flex h-16 items-center justify-center border-b border-slate-200 px-4 py-3">
          <img :src="jattoMark" alt="Jatto Distribuidora" class="h-10 w-auto object-contain" />
        </div>
        <nav class="flex-1 space-y-1 p-3">
          <Link
            v-for="item in nav"
            :key="item.href"
            :href="item.href"
            class="block rounded-lg px-3 py-2 text-sm font-medium transition"
            :class="isActive(item) ? 'bg-indigo-50 text-indigo-700' : 'text-slate-600 hover:bg-slate-100'"
          >
            {{ item.label }}
          </Link>

          <div v-if="adminNav.length" class="mt-4 border-t border-slate-200 pt-4">
            <p class="px-3 pb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">Administração</p>
            <Link
              v-for="item in adminNav"
              :key="item.href"
              :href="item.href"
              class="block rounded-lg px-3 py-2 text-sm font-medium transition"
              :class="isActive(item) ? 'bg-indigo-50 text-indigo-700' : 'text-slate-600 hover:bg-slate-100'"
            >
              {{ item.label }}
            </Link>
          </div>
        </nav>
      </aside>

      <!-- Conteúdo -->
      <!-- min-w-0: permite que este flex item encolha abaixo do conteúdo, para o
           overflow-x-auto das tabelas conter o scroll (senão a página inteira rola). -->
      <div class="min-w-0 flex-1 lg:pl-60">
        <header class="flex h-16 items-center justify-between border-b border-slate-200 bg-white px-6">
          <div class="py-2 lg:hidden">
            <img :src="jattoMark" alt="Jatto Distribuidora" class="h-8 w-auto object-contain" />
          </div>
          <div class="ml-auto flex items-center gap-4">
            <span
              class="hidden items-center gap-1.5 text-xs sm:inline-flex"
              :class="lastSync?.status === 'partial' ? 'text-amber-600' : 'text-slate-400'"
              :title="syncTitle"
            >
              <svg class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path
                  fill-rule="evenodd"
                  d="M15.312 11.424a5.5 5.5 0 01-9.201 2.466l-.312-.311h2.433a.75.75 0 000-1.5H3.989a.75.75 0 00-.75.75v4.242a.75.75 0 001.5 0v-2.43l.31.31a7 7 0 0011.712-3.138.75.75 0 00-1.449-.39zm1.23-3.723a.75.75 0 00.219-.53V2.929a.75.75 0 00-1.5 0V5.36l-.31-.31A7 7 0 003.239 8.188a.75.75 0 101.448.389A5.5 5.5 0 0113.89 6.11l.311.31h-2.432a.75.75 0 000 1.5h4.243a.75.75 0 00.53-.219z"
                  clip-rule="evenodd"
                />
              </svg>
              ERP {{ syncLabel ?? '—' }}
            </span>
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
            v-for="item in [...nav, ...adminNav]"
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
