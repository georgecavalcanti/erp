# Alerta operacional (doc 09.14.2), gravado por Alerts::Scan. Exibido ao admin/gestor.
# Aberto = resolved_at nil; resolvido quando a condição deixa de ocorrer.
class Alert < ApplicationRecord
  # Grupos do doc 09: integração, dados, conciliação, negócio, IA (Sprint 8).
  enum :area, { integration: 0, data: 1, reconciliation: 2, business: 3, ia: 4 }, prefix: :area
  enum :severity, { low: 0, medium: 1, high: 2 }, prefix: :severity

  AREA_LABELS = {
    "integration" => "Integração", "data" => "Dados",
    "reconciliation" => "Conciliação", "business" => "Negócio", "ia" => "IA"
  }.freeze

  validates :key, presence: true
  validates :title, presence: true

  scope :open, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  # Abertos primeiro, depois por severidade e recência.
  scope :ranked, -> { order(Arel.sql("resolved_at IS NULL DESC, severity DESC, last_detected_at DESC")) }

  def area_label
    AREA_LABELS[area]
  end
end
