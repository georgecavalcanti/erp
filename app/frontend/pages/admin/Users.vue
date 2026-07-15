<script setup lang="ts">
import { Head, Link, router } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'

defineOptions({ layout: AppLayout })

interface AdminUser {
  id: number
  email_address: string
  name: string | null
  role: string
  role_label: string
  active: boolean
  salesperson: string | null
  manager: string | null
}

defineProps<{ users: AdminUser[] }>()

function remove(user: AdminUser) {
  if (confirm(`Remover o usuário ${user.email_address}?`)) {
    router.delete(`/admin/usuarios/${user.id}`)
  }
}
</script>

<template>
  <Head title="Usuários" />
  <div class="space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-semibold text-slate-800">Usuários</h1>
        <p class="text-sm text-slate-500">Perfis, vínculo com vendedor e equipe (sem auto-registro)</p>
      </div>
      <Link
        href="/admin/usuarios/new"
        class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700"
      >
        Novo usuário
      </Link>
    </div>

    <div class="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
          <tr>
            <th class="px-4 py-3">E-mail</th>
            <th class="px-4 py-3">Nome</th>
            <th class="px-4 py-3">Perfil</th>
            <th class="px-4 py-3">Vendedor</th>
            <th class="px-4 py-3">Coordenador</th>
            <th class="px-4 py-3">Ativo</th>
            <th class="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="u in users" :key="u.id" class="hover:bg-slate-50">
            <td class="px-4 py-3 font-medium text-slate-700">{{ u.email_address }}</td>
            <td class="px-4 py-3 text-slate-600">{{ u.name || '—' }}</td>
            <td class="px-4 py-3">
              <span class="rounded-full bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700">
                {{ u.role_label }}
              </span>
            </td>
            <td class="px-4 py-3 text-slate-600">{{ u.salesperson || '—' }}</td>
            <td class="px-4 py-3 text-slate-600">{{ u.manager || '—' }}</td>
            <td class="px-4 py-3">
              <span
                class="inline-block h-2 w-2 rounded-full"
                :class="u.active ? 'bg-emerald-500' : 'bg-slate-300'"
                :title="u.active ? 'Ativo' : 'Inativo'"
              ></span>
            </td>
            <td class="px-4 py-3 text-right whitespace-nowrap">
              <Link :href="`/admin/usuarios/${u.id}/edit`" class="text-sm font-medium text-indigo-600 hover:underline">
                Editar
              </Link>
              <button class="ml-3 text-sm font-medium text-red-600 hover:underline" @click="remove(u)">
                Remover
              </button>
            </td>
          </tr>
          <tr v-if="users.length === 0">
            <td colspan="7" class="px-4 py-8 text-center text-slate-400">Nenhum usuário cadastrado.</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
