class Invoice < ApplicationRecord
  belongs_to :company,      optional: true
  belongs_to :partner,      optional: true
  belongs_to :salesperson,  optional: true
  belongs_to :import_batch, optional: true
  has_many :invoice_items, dependent: :delete_all

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
  # Recorte por ano/meses do calendário (meses podem ser não-contíguos: Jan, Mar, Jun).
  scope :in_year,   ->(year) { where("EXTRACT(YEAR FROM negotiation_date) = ?", year.to_i) }
  scope :in_months, ->(months) { where("EXTRACT(MONTH FROM negotiation_date) IN (?)", Array(months).map(&:to_i)) }

  # Só notas confirmadas (STATUSNOTA='L' no ERP). Os relatórios de faturamento
  # contam apenas o que está liberado — nota pendente/cancelada não infla o total
  # nem "gruda" quando some do ERP (o sync incremental é cego a deleção).
  scope :confirmed_only, -> { where(confirmed: true) }

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

  # Margem com sinal (mesma convenção de signed_value): devolução reverte a margem.
  # TODO(Sprint 4+): ao LIGAR margem nos analytics, agregar sempre por
  # signed_margin (não margin_value cru). Senão a margem das devoluções entra
  # positiva e infla o total — o mesmo erro que signed_value evita no faturamento
  # líquido. Hoje ninguém consome margem ainda, por isso é só um lembrete.
  def signed_margin
    return nil if margin_value.nil?

    kind_return? ? -margin_value : margin_value
  end

  # Marca/desmarca pagamento preservando o instante da quitação.
  def mark_paid!(value = true)
    update!(paid: value, paid_at: value ? (paid_at || Time.current) : nil)
  end
end
