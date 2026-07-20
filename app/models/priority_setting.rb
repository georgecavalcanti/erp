# Configuração do motor de priorização (doc 05.4). Singleton: uma linha global.
# PrioritySetting.current devolve a linha ou um default (defaults do doc) — o motor
# funciona sem nenhuma linha gravada.
class PrioritySetting < ApplicationRecord
  belongs_to :updated_by, class_name: "User", optional: true

  DEFAULTS = {
    weight_revenue: 25, weight_conversion: 20, weight_urgency: 15, weight_gap: 15,
    weight_risk: 10, weight_margin: 10, weight_strategic: 5,
    daily_capacity: 12, recent_contact_days: 3
  }.freeze

  WEIGHT_KEYS = %i[revenue conversion urgency gap risk margin strategic].freeze

  def self.current
    first || new(DEFAULTS)
  end

  # Pesos brutos por fator (inteiros).
  def weights
    WEIGHT_KEYS.index_with { |k| public_send("weight_#{k}").to_i }
  end

  # Pesos normalizados (somam 1) — o score é a soma ponderada dos fatores em 0..1.
  def normalized_weights
    raw = weights
    total = raw.values.sum.to_f
    total.zero? ? raw.transform_values { 0.0 } : raw.transform_values { |w| w / total }
  end
end
