# Cockpit do vendedor (doc 08.11.1): meta, realizado, atingimento vs. esperado,
# projeção em 3 cenários, gap e ritmo diário. Home do perfil vendedor.
#
# Escopo: SEMPRE o próprio vendedor (Current.user.salesperson) — não há parâmetro
# de vendedor, então um vendedor nunca abre o cockpit de outro. Calcula ao vivo
# (resiliente sem IA); a persistência append-only fica no ProjectionRecalcJob.
class CockpitController < ApplicationController
  def index
    salesperson = Current.user.salesperson

    render inertia: "Cockpit", props: {
      salesperson: salesperson && { id: salesperson.id, name: salesperson.nickname },
      month: I18n.l(Date.current, format: "%m/%Y"),
      projection: salesperson && serialize(Engines::Projection.new(salesperson).call)
    }
  end

  private

  def serialize(projection)
    {
      business_days: projection[:business_days],
      target: to_f(projection[:target]),
      realized: to_f(projection[:realized]),
      realized_margin: to_f(projection[:realized_margin]),
      expected_to_date: to_f(projection[:expected_to_date]),
      attainment_percent: to_f(projection[:attainment_percent]),
      daily_rhythm_needed: to_f(projection[:daily_rhythm_needed]),
      scenarios: projection[:scenarios].transform_values { |s| serialize_scenario(s) }
    }
  end

  def serialize_scenario(scenario)
    {
      value: to_f(scenario[:value]),
      margin_value: to_f(scenario[:margin_value]),
      confidence: scenario[:confidence],
      gap: to_f(scenario[:gap]),
      components: scenario[:components].map { |c| c.transform_values { |v| v.is_a?(BigDecimal) ? v.to_f : v } }
    }
  end

  def to_f(value)
    value&.to_f
  end
end
