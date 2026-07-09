# Pedido de venda liberado mas ainda não faturado (carteira a faturar).
# É um snapshot: cada import de pedidos pendentes substitui a carteira anterior.
class PendingOrder < ApplicationRecord
  belongs_to :company,      optional: true
  belongs_to :partner,      optional: true
  belongs_to :salesperson,  optional: true
  belongs_to :import_batch, optional: true

  validates :external_uid, presence: true
  validates :total_value, numericality: true

  scope :in_period, ->(range) { where(negotiation_date: range) }
  scope :in_year,   ->(year) { where("EXTRACT(YEAR FROM negotiation_date) = ?", year.to_i) }
  scope :in_months, ->(months) { where("EXTRACT(MONTH FROM negotiation_date) IN (?)", Array(months).map(&:to_i)) }
end
