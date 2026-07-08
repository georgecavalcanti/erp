<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { num } from '@/lib/format'
import type { Pagination } from '@/types/models'

const props = defineProps<{ pagination: Pagination }>()

function go(page: number) {
  const url = new URL(window.location.href)
  url.searchParams.set('page', String(page))
  router.get(`${url.pathname}${url.search}`, {}, { preserveState: true, preserveScroll: true })
}

const btn =
  'rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 ' +
  'hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-40'
</script>

<template>
  <div class="flex items-center justify-between gap-3 text-sm text-slate-500">
    <span>{{ num(pagination.total) }} registros · página {{ pagination.page }} de {{ pagination.pages || 1 }}</span>
    <div class="flex gap-2">
      <button :class="btn" :disabled="pagination.page <= 1" @click="go(pagination.page - 1)">Anterior</button>
      <button :class="btn" :disabled="pagination.page >= pagination.pages" @click="go(pagination.page + 1)">Próxima</button>
    </div>
  </div>
</template>
