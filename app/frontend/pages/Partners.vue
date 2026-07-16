<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import AppLayout from '@/layouts/AppLayout.vue'
import RankingReport from '@/components/RankingReport.vue'
import type { Summary, RankingRow, Evolution, AppliedFilters, FilterOptions } from '@/types/models'

defineOptions({ layout: AppLayout })

defineProps<{
  summary: Summary
  ranking: RankingRow[]
  evolution: Evolution
  filters: AppliedFilters
  filterOptions: FilterOptions
}>()
</script>

<template>
  <Head title="Parceiros" />
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-semibold text-slate-800">Parceiros</h1>
      <p class="text-sm text-slate-500">Faturamento e evolução por empresa parceira</p>
    </div>
    <RankingReport
      entity="Parceiro"
      :summary="summary"
      :ranking="ranking"
      :evolution="evolution"
      :filters="filters"
      :filter-options="filterOptions"
      client-link
    />
  </div>
</template>
