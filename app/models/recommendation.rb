# Recomendação (doc 04/06) — o card com que o vendedor age no Plano do Dia.
# No MVP (Sprint 7) é determinística (vem de uma `priority`); na Sprint 8 o agente
# Claude passa a preenchê-la.
class Recommendation < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :salesperson
  belongs_to :partner, optional: true
  belongs_to :priority, optional: true
  has_many :influenced_revenues, dependent: :destroy

  CHANNELS = { call: 0, whatsapp: 1, visit: 2, email: 3, internal: 4 }.freeze
  STATUSES = { pending: 0, accepted: 1, postponed: 2, discarded: 3, done: 4 }.freeze
  enum :channel, CHANNELS, prefix: :channel
  enum :status, STATUSES, prefix: :status
  enum :feedback, { useful: 0, not_useful: 1 }, prefix: :feedback

  validates :reference_date, presence: true

  scope :for_date, ->(date) { where(reference_date: date) }
  # Ainda em jogo no plano (não descartada nem concluída).
  scope :open, -> { where(status: %i[pending accepted postponed]) }
  scope :ranked, -> { left_joins(:priority).order(Arel.sql("priorities.position NULLS LAST")) }
end
