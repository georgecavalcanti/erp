<script setup lang="ts">
import { computed } from 'vue'
import { Head, Link, useForm } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'

defineOptions({ layout: AppLayout })

interface Option { id: number; name: string }
interface RoleOption { value: string; label: string }
interface AdminUser {
  id: number
  email_address: string
  name: string | null
  role: string
  active: boolean
  salesperson_id: number | null
  manager_id: number | null
}

const props = defineProps<{
  user: AdminUser | null
  options: { roles: RoleOption[]; salespeople: Option[]; managers: Option[] }
}>()

const editing = computed(() => props.user !== null)

const form = useForm({
  email_address: props.user?.email_address ?? '',
  name: props.user?.name ?? '',
  password: '',
  role: props.user?.role ?? 'vendedor',
  salesperson_id: props.user?.salesperson_id ?? null,
  manager_id: props.user?.manager_id ?? null,
  active: props.user?.active ?? true,
})

// Só vendedor/representante exigem vínculo com um vendedor do ERP.
const needsSalesperson = computed(() => ['vendedor', 'representante'].includes(form.role))

function submit() {
  if (editing.value) {
    form.transform((d) => (d.password === '' ? { ...d, password: undefined } : d))
    form.patch(`/admin/usuarios/${props.user!.id}`)
  } else {
    form.post('/admin/usuarios')
  }
}
</script>

<template>
  <Head :title="editing ? 'Editar usuário' : 'Novo usuário'" />
  <div class="mx-auto max-w-2xl space-y-6">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-semibold text-slate-800">{{ editing ? 'Editar usuário' : 'Novo usuário' }}</h1>
      <Link href="/admin/usuarios" class="text-sm font-medium text-slate-500 hover:underline">← Voltar</Link>
    </div>

    <form class="space-y-4 rounded-lg border border-slate-200 bg-white p-6" @submit.prevent="submit">
      <div>
        <label class="mb-1 block text-sm font-medium text-slate-600">E-mail</label>
        <input v-model="form.email_address" type="email" required
               class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500" />
        <p v-if="form.errors.email_address" class="mt-1 text-xs text-red-600">{{ form.errors.email_address }}</p>
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-slate-600">Nome</label>
        <input v-model="form.name" type="text"
               class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500" />
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-slate-600">
          Senha <span v-if="editing" class="font-normal text-slate-400">(deixe em branco para manter)</span>
        </label>
        <input v-model="form.password" type="password" autocomplete="new-password" :required="!editing"
               class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500" />
        <p v-if="form.errors.password" class="mt-1 text-xs text-red-600">{{ form.errors.password }}</p>
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-slate-600">Perfil</label>
        <select v-model="form.role"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500">
          <option v-for="r in options.roles" :key="r.value" :value="r.value">{{ r.label }}</option>
        </select>
      </div>

      <div v-if="needsSalesperson">
        <label class="mb-1 block text-sm font-medium text-slate-600">Vendedor (ERP)</label>
        <select v-model="form.salesperson_id"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500">
          <option :value="null">— selecione —</option>
          <option v-for="s in options.salespeople" :key="s.id" :value="s.id">{{ s.name }}</option>
        </select>
        <p v-if="form.errors.salesperson_id" class="mt-1 text-xs text-red-600">{{ form.errors.salesperson_id }}</p>
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-slate-600">Coordenador (equipe)</label>
        <select v-model="form.manager_id"
                class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500">
          <option :value="null">— nenhum —</option>
          <option v-for="m in options.managers" :key="m.id" :value="m.id">{{ m.name }}</option>
        </select>
      </div>

      <label class="flex items-center gap-2 text-sm text-slate-600">
        <input v-model="form.active" type="checkbox" class="rounded border-slate-300 text-red-600 focus:ring-red-500" />
        Ativo
      </label>

      <div class="flex justify-end gap-3 pt-2">
        <Link href="/admin/usuarios" class="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50">
          Cancelar
        </Link>
        <button type="submit" :disabled="form.processing"
                class="rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50">
          {{ form.processing ? 'Salvando…' : 'Salvar' }}
        </button>
      </div>
    </form>
  </div>
</template>
