module Engines
  # Expansão de mix (doc 05.3). Categorias compradas por clientes SEMELHANTES e
  # ausentes neste cliente → oportunidade de cross-sell. Determinístico, local.
  #
  # "Semelhante" = mesma UF + porte parecido (faixa de receita 12m). O campo
  # `segment` do ERP não serve (99% dos parceiros são "<SEM TIPO PARCEIRO>"), então
  # o porte por receita é o discriminador real.
  #
  #   potencial da categoria = ticket médio (líquido 12m) dela entre os pares que a
  #   compram — o que este cliente deixaria de faturar por não ter a categoria.
  #
  #   Engines::CrossSell.new(partner).call(limit: 5)
  class CrossSell
    LOOKBACK = 12          # meses de histórico considerado
    BAND_LOW = 0.4         # porte: pares com receita entre 0,4× e 2,5× a do cliente
    BAND_HIGH = 2.5
    MAX_PEERS = 150        # teto de pares (os mais próximos em receita)
    MIN_PEERS_BUYING = 3   # categoria só entra se ≥3 pares a compram (sinal, não ruído)

    def initialize(partner, as_of: Date.current)
      @partner = partner
      @as_of = as_of
    end

    # [{ category_external_code, category_name, peers_buying, potential_value }]
    def call(limit: 5)
      peers = peer_ids
      return [] if peers.size < MIN_PEERS_BUYING

      mine = my_categories
      peer_category_values(peers).filter_map do |(code, name), nets|
        next if code.nil? || code.zero? || mine.include?(code) || nets.size < MIN_PEERS_BUYING

        # potencial = MEDIANA do líquido 12m da categoria entre os pares (robusto a
        # outliers — um par com contrato gigante não infla a oportunidade).
        { category_external_code: code, category_name: name, peers_buying: nets.size,
          potential_value: median(nets).round(2) }
      end.sort_by { |c| -c[:potential_value] }.first(limit)
    end

    private

    # Receita líquida (12m) do parceiro — base do porte.
    def my_revenue
      @my_revenue ||= net_12m(@partner.id)[@partner.id] || 0.0
    end

    def my_categories
      @my_categories ||= item_scope([ @partner.id ]).distinct.pluck(Arel.sql("products.category_external_code")).compact.to_set
    end

    # Pares: mesma UF, ativos, com receita 12m na faixa de porte, os MAX_PEERS mais
    # próximos em receita. Sem UF ou sem receita própria → sem base de comparação.
    def peer_ids
      return [] if @partner.state.blank? || my_revenue <= 0

      low = my_revenue * BAND_LOW
      high = my_revenue * BAND_HIGH
      candidates = Partner.active.where(state: @partner.state).where.not(id: @partner.id).pluck(:id)
      return [] if candidates.empty?

      revs = net_12m(candidates)
      revs.select { |_pid, r| r.between?(low, high) }
          .sort_by { |_pid, r| (r - my_revenue).abs }
          .first(MAX_PEERS).map(&:first)
    end

    # Por categoria dos pares: { [code, name] => [líquido 12m de cada par que compra] }.
    def peer_category_values(peers)
      per_partner = item_scope(peers)
                    .group(Arel.sql("products.category_external_code"), Arel.sql("products.category_name"), Arel.sql("invoices.partner_id"))
                    .sum("invoice_items.net_value")
      values = Hash.new { |h, k| h[k] = [] }
      per_partner.each do |(code, name, _pid), net|
        values[[ code, name ]] << net.to_f if net.to_f > 0
      end
      values
    end

    def median(values)
      sorted = values.sort
      n = sorted.size
      mid = n / 2
      n.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Itens de VENDA (produto cadastrado) dos parceiros no período, líquido.
    def item_scope(partner_ids)
      InvoiceItem.joins(:invoice).joins("INNER JOIN products ON products.id = invoice_items.product_id")
                 .where(invoices: { partner_id: partner_ids, confirmed: true, kind: Invoice.kinds[:sale] })
                 .where("invoices.negotiation_date >= ?", @as_of - LOOKBACK.months)
    end

    # Receita líquida 12m por parceiro (venda − devolução).
    def net_12m(ids)
      range = (@as_of - LOOKBACK.months)..@as_of
      sales = Invoice.confirmed_only.sales.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      returns = Invoice.confirmed_only.returns.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      net = Hash.new(0.0)
      sales.each { |pid, v| net[pid] += v.to_f }
      returns.each { |pid, v| net[pid] -= v.to_f }
      net
    end
  end
end
