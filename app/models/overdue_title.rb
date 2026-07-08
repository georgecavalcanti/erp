# Título vencido (inadimplência) importado do relatório manual multi-aba.
# É um snapshot: cada import de inadimplência substitui o conjunto anterior.
class OverdueTitle < ApplicationRecord
  belongs_to :import_batch, optional: true
  belongs_to :salesperson, optional: true
  belongs_to :partner, optional: true

  # open = em aberto (atual) · protested = protestado (cobrança judicial)
  enum :category, { open: 0, protested: 1 }, prefix: :category

  validates :salesperson_label, presence: true
  validates :amount, numericality: true

  scope :open_titles, -> { where(category: :open) }
  scope :protested_titles, -> { where(category: :protested) }
  scope :for_due_month, ->(date) { where(due_date: date.beginning_of_month..date.end_of_month) }
end
