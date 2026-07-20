module Engines
  # Detecção de queda de consumo (doc 05.3). Compara uma janela RECENTE com a
  # linha de base histórica do cliente (mesma duração de janela, normalizada). Sem
  # IA, determinístico. Alimenta o motor de Risco e, adiante, o cross-sell.
  #
  #   recente  = líquido dos últimos RECENT_DAYS
  #   baseline = líquido médio por janela de RECENT_DAYS no histórico anterior
  #   queda    = (baseline − recente) / baseline
  #
  #   Engines::ConsumptionDrop.new(partner).call                 # um parceiro
  #   Engines::ConsumptionDrop.for_partners(ids, as_of:)         # lote (carteira)
  class ConsumptionDrop
    RECENT_DAYS = 90
    BASELINE_DAYS = 360      # 12 meses anteriores à janela recente
    DROP_THRESHOLD = 0.25    # queda ≥ 25% = significativa (vira sinal de risco)
    GROWTH_THRESHOLD = 0.15  # crescimento ≥ 15% = expansão

    def initialize(partner, as_of: Date.current)
      @partner = partner
      @as_of = as_of
    end

    def call
      self.class.for_partners([ @partner.id ], as_of: @as_of)[@partner.id]
    end

    # { partner_id => { recent_net:, baseline_net:, drop_percent:, absolute_lost:, trend: } }
    # trend: :growth · :drop · :stable · :none (sem base histórica)
    def self.for_partners(ids, as_of: Date.current)
      ids = ids.to_a
      return {} if ids.empty?

      recent_from = as_of - RECENT_DAYS
      base_from = as_of - RECENT_DAYS - BASELINE_DAYS
      base_to = as_of - RECENT_DAYS

      recent = net_by_partner(ids, recent_from..as_of)
      baseline_total = net_by_partner(ids, base_from...base_to)

      ids.index_with do |id|
        # baseline total dos 360d reduzido à taxa de uma janela de RECENT_DAYS
        baseline_net = (baseline_total[id] || 0.0) / BASELINE_DAYS * RECENT_DAYS
        build(recent[id] || 0.0, baseline_net)
      end
    end

    def self.build(recent_net, baseline_net)
      drop_percent = baseline_net.positive? ? ((baseline_net - recent_net) / baseline_net * 100).round(1) : nil
      trend =
        if baseline_net <= 0
          recent_net.positive? ? :growth : :none
        elsif recent_net >= baseline_net * (1 + GROWTH_THRESHOLD)
          :growth
        elsif recent_net <= baseline_net * (1 - DROP_THRESHOLD)
          :drop
        else
          :stable
        end
      {
        recent_net: recent_net.round(2), baseline_net: baseline_net.round(2),
        drop_percent: drop_percent, absolute_lost: [ baseline_net - recent_net, 0.0 ].max.round(2), trend: trend
      }
    end
    private_class_method :build

    # Líquido (venda − devolução) por parceiro no intervalo — 2 queries agregadas.
    def self.net_by_partner(ids, range)
      sales = Invoice.confirmed_only.sales.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      returns = Invoice.confirmed_only.returns.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      net = Hash.new(0.0)
      sales.each { |pid, v| net[pid] += v.to_f }
      returns.each { |pid, v| net[pid] -= v.to_f }
      net
    end
    private_class_method :net_by_partner
  end
end
