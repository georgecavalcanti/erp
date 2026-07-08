<script setup lang="ts">
import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'

const page = usePage()
const flash = computed(() => page.props.flash ?? {})
</script>

<template>
  <div v-if="flash.notice || flash.alert" class="mb-4 space-y-2">
    <div v-if="flash.notice" class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
      {{ flash.notice }}
    </div>
    <div v-if="flash.alert" class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
      {{ flash.alert }}
    </div>
  </div>
</template>
