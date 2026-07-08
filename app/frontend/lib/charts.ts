// Registro tree-shaken do ECharts + paleta e helpers compartilhados.
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { BarChart, LineChart, PieChart } from 'echarts/charts'
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  DatasetComponent,
  AxisPointerComponent,
} from 'echarts/components'
import { brl, brlCompact } from './format'

use([
  CanvasRenderer,
  BarChart,
  LineChart,
  PieChart,
  GridComponent,
  TooltipComponent,
  LegendComponent,
  DatasetComponent,
  AxisPointerComponent,
])

// Paleta categórica consistente (acessível em fundo claro).
export const PALETTE = [
  '#4f46e5', // indigo
  '#0ea5e9', // sky
  '#10b981', // emerald
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // violet
  '#ec4899', // pink
  '#14b8a6', // teal
  '#f97316', // orange
  '#64748b', // slate
]

export const STATUS_COLORS = {
  paid: '#10b981',
  overdue: '#ef4444',
  pending: '#f59e0b',
}

// Formatação de eixo monetário compacto (R$ 1,2 mi).
export function moneyAxis(value: number): string {
  return brlCompact(value)
}

export function moneyTooltip(value: number): string {
  return brl(value)
}

export const GRID = { left: 8, right: 16, top: 24, bottom: 8, containLabel: true }
