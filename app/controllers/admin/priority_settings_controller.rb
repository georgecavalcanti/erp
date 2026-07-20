module Admin
  # Configuração do motor de priorização (doc 05.4) — pesos dos fatores do score,
  # capacidade diária e limiares das restrições. Gestor + admin. Singleton.
  class PrioritySettingsController < BaseController
    def index
      render inertia: "admin/PrioritySettings", props: { setting: serialize(PrioritySetting.current) }
    end

    def update
      setting = PrioritySetting.first_or_initialize
      if setting.update(setting_params.merge(updated_by: Current.user))
        redirect_to admin_priorizacao_path, notice: "Configuração de priorização salva."
      else
        redirect_to admin_priorizacao_path, inertia: { errors: setting.errors }
      end
    end

    private

    def setting_params
      params.permit(:weight_revenue, :weight_conversion, :weight_urgency, :weight_gap,
                    :weight_risk, :weight_margin, :weight_strategic,
                    :daily_capacity, :recent_contact_days, :min_margin_percent)
    end

    def serialize(s)
      {
        weight_revenue: s.weight_revenue, weight_conversion: s.weight_conversion,
        weight_urgency: s.weight_urgency, weight_gap: s.weight_gap, weight_risk: s.weight_risk,
        weight_margin: s.weight_margin, weight_strategic: s.weight_strategic,
        daily_capacity: s.daily_capacity, recent_contact_days: s.recent_contact_days,
        min_margin_percent: s.min_margin_percent&.to_f,
        normalized: s.normalized_weights.transform_values { |v| (v * 100).round(1) }
      }
    end
  end
end
