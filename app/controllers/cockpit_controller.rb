# Cockpit do vendedor (doc 08.11.1): meta, realizado, atingimento vs. esperado,
# projeção em 3 cenários, gap e ritmo diário. Home do perfil vendedor.
#
# Escopo: SEMPRE o próprio vendedor (Current.user.salesperson) — não há parâmetro
# de vendedor, então um vendedor nunca abre o cockpit de outro. Calcula ao vivo
# (resiliente sem IA); a persistência append-only fica no ProjectionRecalcJob.
class CockpitController < ApplicationController
  # Pergunta fixa do "Resumo do Claude" (Sprint 8): interpretação curta da
  # posição — os números o agente busca pelas ferramentas.
  SUMMARY_PROMPT = "Resuma minha posição comercial do mês em até 4 frases curtas: " \
                   "atingimento vs. esperado até hoje, gap para a meta, o principal risco na carteira " \
                   "e a ação nº 1 de hoje. Sem cards: responda com recomendacoes: [].".freeze

  def index
    salesperson = Current.user.salesperson
    last = AgentRun.last_valid(user: Current.user, kind: :cockpit_summary)

    render inertia: "Cockpit", props: {
      salesperson: salesperson && { id: salesperson.id, name: salesperson.nickname },
      month: I18n.l(Date.current, format: "%m/%Y"),
      projection: salesperson && serialize(Engines::Projection.new(salesperson).call),
      agentEnabled: Agent::Config.enabled?,
      claudeSummary: last && { resumo: last.output["resumo"], generated_at: last.created_at.iso8601 }
    }
  end

  # Gera/atualiza o resumo pelo agente (kind cockpit_summary → Haiku). Falha ou
  # IA fora do ar degrada com aviso — o cockpit continua funcionando (MVP 13).
  def resumo
    salesperson = Current.user.salesperson
    return redirect_to cockpit_path, alert: "Sem vendedor vinculado ao usuário." unless salesperson

    result = Agent::Orchestrator.new(user: Current.user, salesperson: salesperson, kind: :cockpit_summary)
                                .run(SUMMARY_PROMPT)
    if result.degraded
      redirect_to cockpit_path, alert: result.aviso
    else
      redirect_to cockpit_path, notice: "Resumo do Claude atualizado."
    end
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
