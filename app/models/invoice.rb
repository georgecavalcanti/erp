class Invoice < ApplicationRecord
  belongs_to :company,      optional: true
  belongs_to :partner,      optional: true
  belongs_to :salesperson,  optional: true
  belongs_to :import_batch, optional: true

  # Venda vs Devolução. Prefixo evita colidir com a palavra reservada `return`.
  enum :kind, { sale: 0, return: 1 }, prefix: :kind

  validates :external_uid, presence: true, uniqueness: true
  validates :negotiation_date, presence: true
  validates :total_value, numericality: true

  # --- Escopos de recorte ---
  scope :sales,   -> { kind_sale }
  scope :returns, -> { kind_return }
  scope :in_period, ->(range) { where(negotiation_date: range) }
  scope :for_month, ->(date) { where(negotiation_date: date.beginning_of_month..date.end_of_month) }

  # --- Escopos de pagamento (aplicáveis a vendas) ---
  scope :unpaid,    -> { where(paid: false) }
  scope :paid_only, -> { where(paid: true) }
  # Inadimplente: venda não paga cujo vencimento já passou.
  scope :overdue, ->(as_of = Date.current) { sales.unpaid.where.not(due_date: nil).where(due_date: ...as_of) }
  # A vencer: venda não paga ainda dentro do prazo.
  scope :upcoming, ->(as_of = Date.current) { sales.unpaid.where("due_date IS NULL OR due_date >= ?", as_of) }

  PAYMENT_STATUSES = %w[paid overdue pending].freeze

  # Status de pagamento derivado (não persistido).
  #   paid    -> pago
  #   overdue -> inadimplente (vencido e não pago)
  #   pending -> a vencer
  def payment_status(as_of = Date.current)
    return "paid" if paid?
    return "overdue" if due_date.present? && due_date < as_of

    "pending"
  end

  def overdue?(as_of = Date.current)
    payment_status(as_of) == "overdue"
  end

  # Valor com sinal: devoluções entram negativas no faturamento líquido.
  def signed_value
    kind_return? ? -total_value : total_value
  end

  # Marca/desmarca pagamento preservando o instante da quitação.
  def mark_paid!(value = true)
    update!(paid: value, paid_at: value ? (paid_at || Time.current) : nil)
  end
end
