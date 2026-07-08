const MONTHS_PT = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

const brlFormatter = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
const brlCompactFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
})
const numberFormatter = new Intl.NumberFormat('pt-BR')

export function brl(value: number | null | undefined): string {
  return brlFormatter.format(value ?? 0)
}

export function brlCompact(value: number | null | undefined): string {
  return brlCompactFormatter.format(value ?? 0)
}

export function num(value: number | null | undefined): string {
  return numberFormatter.format(value ?? 0)
}

export function percent(value: number | null | undefined, digits = 1): string {
  return `${(value ?? 0).toFixed(digits).replace('.', ',')}%`
}

// "2026-07" -> "jul/26"
export function monthLabel(ym: string): string {
  const [year, month] = ym.split('-').map(Number)
  return `${MONTHS_PT[(month ?? 1) - 1]}/${String(year).slice(2)}`
}

// ISO date/datetime -> "dd/mm/aaaa"
export function dateBR(iso: string | null | undefined): string {
  if (!iso) return '—'
  const value = iso.length <= 10 ? `${iso}T00:00:00` : iso
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleDateString('pt-BR')
}
