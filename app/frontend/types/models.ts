// Tipos espelhando os props emitidos pelos controllers (Analytics/InvoiceSerializer).

export interface Summary {
  gross_sales: number
  returns_total: number
  net_revenue: number
  commission_total: number
  invoice_count: number
  avg_ticket: number
}

// Inadimplência (resumo importado)
export interface DelinquencySummary {
  open_total: number
  protested_total: number
  protested_by_year: Record<string, number>
  saldo_devedor: number
  salespeople_count: number
  reference_date: string | null
  has_detail: boolean
}

export interface DelinquencyRow {
  name: string
  linked: string | null
  open: number
  protested: number
  saldo: number
}

export interface NamedAmount {
  name: string
  amount: number
}

export interface MonthAmount {
  month: string
  amount: number
}

// Carteira (pedidos pendentes)
export interface PortfolioSummary {
  total: number
  count: number
  avg_ticket: number
  by_delivery: Record<string, number>
}

export interface PortfolioSalesperson {
  name: string
  total: number
  count: number
}

export interface PendingOrderRow {
  id: number
  external_uid: number
  partner: string | null
  salesperson: string | null
  negotiation_date: string
  total_value: number
  delivery_type: string | null
  note_status: string | null
}

// Situação geral (reconciliação por vendedor)
export interface SituationRow {
  name: string
  faturamento: number
  devolucoes: number
  liquido: number
  comissao: number
  carteira: number
  inad_aberto: number
  protestado: number
  saldo: number
}

export type SituationTotals = Omit<SituationRow, 'name'>

export interface MonthlyRow {
  month: string
  sales: number
  returns: number
  net: number
  commission: number
  count: number
}

export interface RankingRow {
  id: number
  name: string
  sales: number
  returns: number
  net: number
  commission: number
  count: number
}

export interface EvolutionSeries {
  name: string
  data: number[]
}

export interface Evolution {
  months: string[]
  series: EvolutionSeries[]
}

export interface FilterOption {
  id: number
  name: string
}

export interface FilterOptions {
  years: number[]
  companies: FilterOption[]
  salespeople: FilterOption[]
  partners: FilterOption[]
}

export interface AppliedFilters {
  start: string | null
  end: string | null
  year: number | null
  months: number[]
  company_id: number | null
  salesperson_ids: number[]
  partner_ids: number[]
}

// Influência dos filtros sobre um card/gráfico (usado pelo InfoHint).
export type FilterScope = 'all' | 'partial' | 'none'

// Último sync do Sankhya (shared prop, exibido no cabeçalho).
export interface LastSync {
  at: string
  status: 'ok' | 'partial'
}

export type PaymentStatus = 'paid' | 'overdue' | 'pending'
export type InvoiceKind = 'sale' | 'return'

export interface InvoiceRow {
  id: number
  external_uid: number
  invoice_number: number | null
  order_number: number | null
  company: string | null
  partner: string | null
  salesperson: string | null
  negotiation_date: string
  total_value: number
  commission: number
  payment_terms: string | null
  installment_offsets: number[]
  first_due_date: string | null
  due_date: string | null
  kind: InvoiceKind
  paid: boolean
  paid_at: string | null
  status: PaymentStatus
}

export interface Pagination {
  page: number
  per: number
  total: number
  pages: number
}
