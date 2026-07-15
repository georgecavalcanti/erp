module Engines
  # Motor de projeção de faturamento do mês (doc 05.1). Determinístico e sem IA:
  # combina REALIZADO + CARTEIRA ponderada + TENDÊNCIA (run-rate dos dias restantes)
  # em 3 cenários, cada um com parcelas rastreáveis (`components`) e confiança.
  #
  # MVP: recompra, cotação e cross-sell (Sprints 5-7) entram como novas parcelas
  # quando existirem — a estrutura já suporta. Pesos são constantes por ora
  # (viram configuração de gestor depois, doc 05.4).
  #
  #   Engines::Projection.new(salesperson).call      # calcula (Cockpit, ao vivo)
  #   Engines::Projection.new(salesperson).persist!  # grava a leva (append-only)
  class Projection
    VERSION = "mvp-1".freeze
    METHOD = "realizado+carteira+run_rate".freeze

    # Fração da carteira (pedidos pendentes) esperada em cada cenário.
    PORTFOLIO = { conservative: 0.80, likely: 0.90, potential: 1.00 }.freeze
    # Fração do run-rate (ritmo atual projetado nos dias restantes) por cenário.
    RUN_RATE = { conservative: 0.0, likely: 0.50, potential: 0.90 }.freeze
    CONFIDENCE = { conservative: 90, likely: 72, potential: 48 }.freeze
    SCENARIOS = %i[conservative likely potential].freeze

    def initialize(salesperson, as_of: Date.current)
      @salesperson = salesperson
      @as_of = as_of
    end

    def call
      days = BusinessCalendar.month_stats(@as_of)
      realized = realized_net
      margin_rate = realized.positive? ? (realized_margin / realized) : nil
      portfolio = portfolio_total
      run_rate = run_rate_remaining(realized, days)

      scenarios = SCENARIOS.index_with do |s|
        value = realized + (portfolio * PORTFOLIO[s]) + (run_rate * RUN_RATE[s])
        {
          value: value.round(2),
          margin_value: margin_rate ? (value * margin_rate).round(2) : nil,
          confidence: CONFIDENCE[s],
          gap: target ? (target - value).round(2) : nil,
          components: components_for(s, realized, portfolio, run_rate)
        }
      end

      {
        salesperson_id: @salesperson.id,
        reference_date: @as_of,
        business_days: days,
        target: target&.round(2),
        realized: realized.round(2),
        realized_margin: realized_margin.round(2),
        expected_to_date: expected_to_date(days),   # atingimento ESPERADO até hoje (R$)
        attainment_percent: attainment(realized),   # atingimento REALIZADO (% da meta)
        daily_rhythm_needed: daily_rhythm(realized, days),
        scenarios: scenarios
      }
    end

    # Grava a leva atual (append-only): uma linha por cenário. Devolve o mesmo
    # hash de #call para reaproveitamento.
    def persist!
      result = call
      ::Projection.transaction do
        result[:scenarios].each do |scenario, data|
          ::Projection.create!(
            salesperson_id: @salesperson.id, reference_date: @as_of, scenario: scenario,
            value: data[:value], margin_value: data[:margin_value],
            target_value: result[:target], realized_value: result[:realized], gap_value: data[:gap],
            confidence: data[:confidence], method: METHOD, engine_version: VERSION,
            components: { parcels: data[:components], business_days: result[:business_days] }
          )
        end
      end
      result
    end

    private

    # Notas liberadas do mês, do vendedor. Devolução entra negativa (signed).
    def invoices
      Invoice.confirmed_only.where(salesperson_id: @salesperson.id).for_month(@as_of)
    end

    def realized_net
      (invoices.sales.sum(:total_value) - invoices.returns.sum(:total_value)).to_d
    end

    # Margem realizada com sinal (devolução reverte a margem, como signed_margin).
    # SUM ignora NULL: notas sem itens sincronizados não derrubam o total, só não somam.
    def realized_margin
      (invoices.sales.sum(:margin_value) - invoices.returns.sum(:margin_value)).to_d
    end

    # Carteira a faturar do vendedor (pedidos pendentes, qualquer mês).
    def portfolio_total
      Order.portfolio.where(salesperson_id: @salesperson.id).sum(:total_value).to_d
    end

    # Ritmo atual projetado nos dias úteis restantes. Sem realizado ou sem dias
    # decorridos não há ritmo a extrapolar.
    def run_rate_remaining(realized, days)
      return 0.to_d if realized <= 0 || days[:elapsed] <= 0

      realized / days[:elapsed] * days[:remaining]
    end

    def target
      return @target if defined?(@target)

      @target = Goal.for_period(@as_of).find_by(salesperson_id: @salesperson.id, kind: :revenue)&.amount
    end

    def expected_to_date(days)
      return nil unless target && days[:total].positive?

      (target * days[:elapsed] / days[:total]).round(2)
    end

    def attainment(realized)
      return nil unless target&.positive?

      (realized / target * 100).round(1)
    end

    # Ritmo diário necessário p/ bater a meta = gap ÷ dias úteis restantes.
    def daily_rhythm(realized, days)
      return nil unless target

      gap = target - realized
      return 0.to_d if gap <= 0                    # meta já atingida
      return gap.round(2) if days[:remaining] <= 0 # sem dias restantes: precisa de tudo agora

      (gap / days[:remaining]).round(2)
    end

    # Parcelas rastreáveis do cenário (origem + valor) — o agente explica a partir daqui.
    def components_for(scenario, realized, portfolio, run_rate)
      parcels = [ { key: "realizado", label: "Faturado no mês", value: realized.round(2) } ]

      pw = PORTFOLIO[scenario]
      if portfolio.positive?
        parcels << { key: "carteira", label: "Carteira a faturar", weight: pw,
                     base: portfolio.round(2), value: (portfolio * pw).round(2) }
      end

      rw = RUN_RATE[scenario]
      if run_rate.positive? && rw.positive?
        parcels << { key: "tendencia", label: "Ritmo projetado nos dias restantes", weight: rw,
                     base: run_rate.round(2), value: (run_rate * rw).round(2) }
      end
      parcels
    end
  end
end
