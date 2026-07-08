<script setup lang="ts">
import type { PaymentStatus } from '@/types/models'

defineProps<{ status: PaymentStatus }>()

const MAP: Record<PaymentStatus, { label: string; cls: string }> = {
  paid: { label: 'Pago', cls: 'bg-emerald-50 text-emerald-700 ring-emerald-600/20' },
  overdue: { label: 'Vencido', cls: 'bg-red-50 text-red-700 ring-red-600/20' },
  pending: { label: 'A vencer', cls: 'bg-amber-50 text-amber-700 ring-amber-600/20' },
}
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset"
    :class="MAP[status].cls"
  >
    {{ MAP[status].label }}
  </span>
</template>
