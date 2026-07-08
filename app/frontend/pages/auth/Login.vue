<script setup lang="ts">
import { computed } from 'vue'
import { Head, useForm, usePage } from '@inertiajs/vue3'

const form = useForm({ email_address: '', password: '' })
const page = usePage()
const alert = computed(() => page.props.flash?.alert)

function submit() {
  form.post('/session', { onFinish: () => form.reset('password') })
}
</script>

<template>
  <Head title="Entrar" />
  <div class="flex min-h-screen items-center justify-center bg-slate-100 px-4">
    <div class="w-full max-w-sm">
      <div class="mb-6 flex flex-col items-center">
        <div class="mb-3 flex h-12 w-12 items-center justify-center rounded-xl bg-indigo-600 text-lg font-bold text-white">F</div>
        <h1 class="text-lg font-semibold text-slate-800">Painel de Faturamento</h1>
        <p class="text-sm text-slate-500">Acesse com sua conta de administrador</p>
      </div>

      <form class="space-y-4 rounded-xl border border-slate-200 bg-white p-6 shadow-sm" @submit.prevent="submit">
        <div v-if="alert" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
          {{ alert }}
        </div>

        <div>
          <label class="mb-1 block text-sm font-medium text-slate-600">E-mail</label>
          <input
            v-model="form.email_address"
            type="email"
            autocomplete="username"
            required
            class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          />
        </div>

        <div>
          <label class="mb-1 block text-sm font-medium text-slate-600">Senha</label>
          <input
            v-model="form.password"
            type="password"
            autocomplete="current-password"
            required
            class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          />
        </div>

        <button
          type="submit"
          :disabled="form.processing"
          class="w-full rounded-md bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-500 disabled:opacity-50"
        >
          {{ form.processing ? 'Entrando…' : 'Entrar' }}
        </button>
      </form>
    </div>
  </div>
</template>
