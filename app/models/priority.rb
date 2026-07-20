# Prioridade do dia por (vendedor, cliente) — doc 04/05.4. Gravada por
# Engines::Prioritization (snapshot diário). NÃO confundir com o motor.
class Priority < ApplicationRecord
  belongs_to :salesperson
  belongs_to :partner
  has_many :recommendations, dependent: :nullify

  validates :reference_date, presence: true

  scope :for_date, ->(date) { where(reference_date: date) }
  scope :ranked, -> { order(:position) }
end
