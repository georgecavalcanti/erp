# Projeção de faturamento do mês por vendedor (doc 05.1), gravada append-only
# por Engines::Projection#persist!. Uma linha por cenário e por recálculo.
# NÃO confundir com o motor Engines::Projection (que calcula) — este é o registro.
class Projection < ApplicationRecord
  belongs_to :salesperson

  enum :scenario, { conservative: 0, likely: 1, potential: 2 }, prefix: :scenario

  validates :reference_date, presence: true
  validates :value, numericality: true

  scope :for_period, ->(date) { where(reference_date: date.beginning_of_month..date.end_of_month) }
  # Ordena do recálculo mais recente para o mais antigo (a "leva" atual vem primeiro).
  scope :newest_first, -> { order(created_at: :desc) }
end
