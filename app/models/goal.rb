# Meta por vendedor/período (doc 04). Uma por (vendedor, mês, tipo). `period` é
# sempre o 1º dia do mês — normalizado antes de validar.
class Goal < ApplicationRecord
  belongs_to :salesperson
  belongs_to :created_by, class_name: "User", optional: true

  KINDS = { revenue: 0, margin: 1, mix: 2, activation: 3 }.freeze
  enum :kind, KINDS, prefix: :kind

  before_validation :normalize_period

  validates :period, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_margin_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # Meta vinculada a vendedor/período corretos (critério de aceite MVP 4).
  validates :kind, uniqueness: { scope: %i[salesperson_id period] }

  scope :for_period, ->(date) { where(period: date.beginning_of_month) }

  private

  # Aceita qualquer dia do mês na UI, mas guarda sempre o 1º (chave estável).
  def normalize_period
    self.period = period.beginning_of_month if period
  end
end
