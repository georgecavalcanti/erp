module Engines
  # Simulador para alcançar a meta (doc 05.5). Combina o MENOR conjunto de
  # oportunidades capaz de eliminar o gap, por VALOR ESPERADO (potencial ×
  # probabilidade), respeitando a capacidade diária. Heurística gulosa (knapsack
  # simples) — reaproveita a saída de Engines::Prioritization. Determinístico.
  #
  #   Engines::GoalSimulator.new(salesperson).call
  #   => { gap:, projected:, covers_gap:, count:, selected: [...], by_origin: {...} }
  class GoalSimulator
    def initialize(salesperson, as_of: Date.current, config: PrioritySetting.current)
      @salesperson = salesperson
      @as_of = as_of
      @config = config
    end

    def call
      engine = Engines::Prioritization.new(@salesperson, as_of: @as_of, config: @config)
      gap = engine.send(:gap)
      opportunities = engine.call.map { |it| opportunity(it) }.select { |o| o[:expected].positive? }

      selected = greedy_select(opportunities, gap)
      projected = selected.sum { |o| o[:expected] }.round(2)
      {
        gap: gap&.round(2)&.to_f, capacity: @config.daily_capacity, # to_f: o Vue espera number, não BigDecimal
        projected: projected, covers_gap: gap.nil? || gap <= 0 || projected >= gap,
        count: selected.size, selected: selected, by_origin: group_by_origin(selected)
      }
    end

    private

    # Valor esperado = potencial × probabilidade de conversão (fator do score).
    def opportunity(item)
      prob = item.dig(:score_factors, :conversion, :value).to_f
      potential = item[:potential_value].to_f
      {
        partner_id: item[:partner_id], potential: potential.round(2), probability: prob.round(4),
        expected: (potential * prob).round(2), origin: origin_of(item), reasons: item[:reasons]
      }
    end

    # Guloso por valor esperado: acumula até cobrir o gap ou esgotar a capacidade.
    # Sem meta/gap (nil ou ≤ 0): devolve as melhores oportunidades até a capacidade.
    def greedy_select(opportunities, gap)
      sorted = opportunities.sort_by { |o| -o[:expected] }
      selected = []
      acc = 0.0
      sorted.each do |o|
        break if selected.size >= @config.daily_capacity
        break if gap&.positive? && acc >= gap

        selected << o
        acc += o[:expected]
      end
      selected
    end

    # Origem predominante da oportunidade (para o resumo por fonte, doc 05.5).
    def origin_of(item)
      keys = item[:reasons].map { |r| r[:key] }
      return "recompra" if keys.include?("recompra_atrasada")
      return "risco" if keys.include?("risco") || keys.include?("queda_consumo")
      return "financeiro" if keys.include?("inadimplencia")

      "relacionamento"
    end

    def group_by_origin(selected)
      selected.group_by { |o| o[:origin] }.transform_values do |list|
        { count: list.size, expected: list.sum { |o| o[:expected] }.round(2) }
      end
    end
  end
end
