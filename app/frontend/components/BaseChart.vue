<script setup lang="ts">
import VChart from 'vue-echarts'
import type { EChartsCoreOption } from 'echarts/core'
import '@/lib/charts'

withDefaults(defineProps<{ option: EChartsCoreOption; height?: number }>(), {
  height: 320,
})
</script>

<template>
  <VChart :option="option" autoresize :style="{ height: `${height}px`, width: '100%' }" />
</template>
