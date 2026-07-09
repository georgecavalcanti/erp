<script setup lang="ts">
import { computed } from 'vue'
import { Head, useForm, usePage } from '@inertiajs/vue3'
import jattoHero from '@/assets/jatto-hero.jpg'
import jattoMark from '@/assets/jatto-mark.png'

const form = useForm({ email_address: '', password: '' })
const page = usePage()
const alert = computed(() => page.props.flash?.alert)

function submit() {
  form.post('/session', { onFinish: () => form.reset('password') })
}
</script>

<template>
  <Head title="Entrar" />
  <div class="flex min-h-screen bg-slate-50">
    <!-- Marca (desktop): arte inteira e centralizada sobre o vermelho da Jatto -->
    <div class="hidden bg-[#9e0208] lg:block lg:w-1/2">
      <img :src="jattoHero" alt="Jatto Distribuidora" class="h-full w-full object-cover" />
    </div>

    <!-- Formulário -->
    <div class="flex w-full items-center justify-center px-4 py-12 lg:w-1/2">
      <div class="w-full max-w-sm">
        <div class="mb-8 flex justify-center py-6">
          <img :src="jattoMark" alt="Jatto Distribuidora" class="w-56 object-contain" />
        </div>

        <form
          class="space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-lg shadow-slate-200/60"
          @submit.prevent="submit"
        >
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
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
            />
          </div>

          <div>
            <label class="mb-1 block text-sm font-medium text-slate-600">Senha</label>
            <input
              v-model="form.password"
              type="password"
              autocomplete="current-password"
              required
              class="w-full rounded-md border-slate-300 text-sm shadow-sm focus:border-red-500 focus:ring-red-500"
            />
          </div>

          <button
            type="submit"
            :disabled="form.processing"
            class="w-full rounded-md bg-red-600 px-3 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-red-700 disabled:opacity-50"
          >
            {{ form.processing ? 'Entrando…' : 'Entrar' }}
          </button>
        </form>

        <p class="mt-6 text-center text-xs text-slate-400">Jatto Distribuidora · acesso restrito</p>
      </div>
    </div>
  </div>
</template>
