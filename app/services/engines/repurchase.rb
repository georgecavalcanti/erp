module Engines
  # Motor de recompra (doc 05.2) — estágio ESTATÍSTICO, determinístico e sem IA.
  # Para cada nível (cliente / cliente+categoria / cliente+produto):
  #
  #   data esperada  = última compra + MEDIANA do intervalo entre compras
  #   confiança      = fator de ciclos × regularidade  (∝ nº de ciclos observados
  #                    e inversamente ∝ à dispersão dos intervalos)
  #
  # Regra: NÃO prever recompra do que já está em pedido aberto (Order.portfolio) —
  # o parceiro já está no pipeline daquele alvo.
  #
  # Mesmo desenho de Engines::Projection: motor PURO (#call) + persistência
  # append-only (#persist!). A conciliação (#reconcile!) fecha o laço de
  # aprendizado: compra real cobrindo a previsão → confirmed; venceu sem compra
  # nem pedido → missed.
  #
  #   Engines::Repurchase.new(partner).call        # previsões atuais (sem gravar)
  #   Engines::Repurchase.new(partner).persist!    # grava as abertas (idempotente)
  #   Engines::Repurchase.new(partner).reconcile!  # confirma/expira as abertas
  class Repurchase
    VERSION = "stat-1".freeze
    METHOD = "mediana-intervalo".freeze

    SATURATION_CYCLES = 6      # nº de ciclos em que o fator de ciclo satura em 1,0
    MAX_CONFIDENCE = 95        # estatística nunca é certeza absoluta
    CUSTOMER_MIN_EVENTS = 2    # nível cliente: ≥2 compras (1 intervalo) p/ prever
    ITEM_MIN_EVENTS = 3        # categoria/produto: só o recorrente de fato (≥3 compras)
    # Tolerância de atraso (≈ um ciclo, entre 15 e 90 dias). Enquanto a previsão
    # está vencida DENTRO da tolerância é "recompra atrasada" (acionável, aparece na
    # carteira); ALÉM da tolerância o cliente quebrou a cadência → vira `missed` e
    # não é regerada (é caso de INATIVIDADE, tratado por Engines::Risk). Isso evita
    # churn de previsões perpetuamente atrasadas de clientes dormentes.
    MIN_TOLERANCE = 15
    MAX_TOLERANCE = 90
    MAX_ITEM_PREDICTIONS = 25  # teto por nível (categoria/produto): foca no recorrente

    def initialize(partner, as_of: Date.current)
      @partner = partner
      @as_of = as_of
    end

    # Previsões atuais (uma por alvo com histórico suficiente), sem persistir.
    def call
      [ customer_prediction, *category_predictions, *product_predictions ].compact
    end

    # Grava as previsões abertas de forma IDEMPOTENTE: se já existe uma aberta para
    # o alvo com a MESMA previsão (âncora, data esperada e intervalo), não duplica;
    # se QUALQUER um mudou, cancela a antiga (superada) e grava a nova. Comparar a
    # data esperada — não só a âncora — cobre a mutação no MEIO do histórico (ex.:
    # estorno de nota intermediária pelo reconcile do sync muda a mediana/expected
    # sem mexer na última compra). Casado com o índice parcial único.
    def persist!
      created = []
      RepurchasePrediction.transaction do
        call.each do |pred|
          existing = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: pred[:target_key])
          if existing
            next if unchanged?(existing, pred) # nada mudou

            existing.update!(status: :canceled, resolved_at: Time.current) # superada por recálculo
          end
          created << RepurchasePrediction.create!(persist_attributes(pred))
        end
      end
      created
    end

    # Concilia as previsões ABERTAS do parceiro com a realidade (aprendizado):
    #   compra do alvo após a âncora        → confirmed + confirmed_invoice_id
    #   venceu (expected+grace) sem compra
    #   nem pedido aberto cobrindo o alvo   → missed
    def reconcile!(as_of: @as_of)
      resolved = { confirmed: 0, missed: 0 }
      RepurchasePrediction.status_open.where(partner_id: @partner.id).find_each do |pred|
        if (invoice = confirming_invoice(pred))
          pred.update!(status: :confirmed, confirmed_invoice_id: invoice.id, resolved_at: Time.current,
                       actual_date: invoice.negotiation_date, actual_value: invoice.total_value)
          resolved[:confirmed] += 1
        elsif overdue_missed?(pred, as_of)
          pred.update!(status: :missed, resolved_at: Time.current)
          resolved[:missed] += 1
        end
      end
      resolved
    end

    private

    # ---- Geração por nível ------------------------------------------------------

    # Nível CLIENTE: cadência geral de compra. Suprimido se há pedido aberto — o
    # parceiro já está no pipeline (doc 05.2).
    def customer_prediction
      return nil if open_orders.exists?

      events = Invoice.confirmed_only.sales.where(partner_id: @partner.id)
                      .group(:negotiation_date).sum(:total_value)
                      .map { |date, value| { date: date, value: value.to_d, quantity: nil } }
      stats = predict(events, CUSTOMER_MIN_EVENTS)
      return nil unless stats

      base_prediction(:customer, "customer", stats)
    end

    # Nível CATEGORIA: cadência por grupo de produto (TGFGRU). Pula categorias já
    # presentes em pedido aberto.
    def category_predictions
      # Sem quantidade: uma categoria (TGFGRU) reúne SKUs de UNIDADES diferentes
      # (PAR, UN, KG…); somar quantidades seria um número sem sentido. A quantidade
      # esperada só existe no nível PRODUTO.
      series = item_series(%w[code name], track_quantity: false)
      blocked = open_order_category_codes
      preds = series.filter_map do |(code, name), events|
        next if code.nil? || code.zero? || blocked.include?(code) # 0/nil = sem grupo real

        stats = predict(events, ITEM_MIN_EVENTS)
        next unless stats

        base_prediction(:category, "category:#{code}", stats)
          .merge(category_external_code: code, category_name: name)
      end
      top(preds)
    end

    # Nível PRODUTO: cadência por SKU. Pula produtos já presentes em pedido aberto.
    def product_predictions
      series = item_series(%w[product_id description], track_quantity: true)
      blocked = open_order_product_ids
      preds = series.filter_map do |(product_id, _description), events|
        next if blocked.include?(product_id)

        stats = predict(events, ITEM_MIN_EVENTS)
        next unless stats

        base_prediction(:product, "product:#{product_id}", stats).merge(product_id: product_id)
      end
      top(preds)
    end

    # Séries temporais de compra por chave (categoria ou produto): { chave =>
    # [{date, value, quantity}, ...] }. Só itens de VENDA com produto cadastrado.
    # `keys` seleciona as colunas de agrupamento (código+nome da categoria, ou
    # id+descrição do produto).
    def item_series(kind, track_quantity:)
      group_cols =
        if kind == %w[code name]
          [ Arel.sql("products.category_external_code"), Arel.sql("products.category_name") ]
        else
          [ Arel.sql("invoice_items.product_id"), Arel.sql("products.description") ]
        end
      base = sale_items.group(*group_cols, Arel.sql("invoices.negotiation_date"))
      values = base.sum("invoice_items.net_value")
      quantities = track_quantity ? base.sum("invoice_items.quantity") : {}

      series = Hash.new { |h, k| h[k] = [] }
      values.each do |(k1, k2, date), value|
        qty = track_quantity ? quantities[[ k1, k2, date ]].to_d : nil
        series[[ k1, k2 ]] << { date: date, value: value.to_d, quantity: qty }
      end
      series
    end

    # ---- Estatística (núcleo determinístico) ------------------------------------

    # events: [{date:, value:, quantity:}] (qualquer ordem, uma por dia de compra).
    # Devolve nil se não há ciclos suficientes.
    def predict(events, min_events)
      events = events.reject { |e| e[:value].to_d <= 0 }.sort_by { |e| e[:date] } # dia líquido ≤ 0 não é compra
      dates = events.map { |e| e[:date] }
      return nil if dates.size < min_events

      intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }.reject { |d| d <= 0 }
      return nil if intervals.empty?

      median_interval = median(intervals).round
      expected_date = dates.last + median_interval
      # Previsão obsoleta (vencida além da tolerância): o cliente quebrou a cadência
      # — vira sinal de inatividade (Risco), não recompra viva. Não gera.
      return nil if expected_date + tolerance(median_interval) < @as_of

      quantities = events.filter_map { |e| e[:quantity] }
      {
        last_purchase_on: dates.last,
        expected_date: expected_date,
        expected_value: median(events.map { |e| e[:value] }).round(2),
        expected_quantity: quantities.any? ? median(quantities).round(4) : nil,
        interval_days: median_interval,
        cycles: intervals.size,
        confidence: confidence_for(intervals),
        components: {
          intervals: intervals, median_interval: median_interval,
          mean_interval: mean(intervals).round(2), cv: coefficient_of_variation(intervals).round(4),
          events: dates.size, first_purchase_on: dates.first.to_s, last_purchase_on: dates.last.to_s
        }
      }
    end

    # Confiança = fator de ciclos × regularidade, em 0..MAX_CONFIDENCE.
    #   fator de ciclos = min(nº intervalos / SATURATION_CYCLES, 1)   (∝ ciclos)
    #   regularidade    = 1 / (1 + CV)   (CV=0 → 1; CV=1 → 0,5)       (∝ 1/dispersão)
    # Um único intervalo tem CV=0 (regularidade 1) mas fator de ciclos baixo → a
    # confiança fica naturalmente baixa com poucos ciclos, sem caso especial.
    def confidence_for(intervals)
      cycle_factor = [ intervals.size / SATURATION_CYCLES.to_f, 1.0 ].min
      regularity = 1.0 / (1.0 + coefficient_of_variation(intervals))
      (100 * cycle_factor * regularity).round.clamp(0, MAX_CONFIDENCE)
    end

    def coefficient_of_variation(values)
      m = mean(values)
      return 0.0 if m.zero?

      Math.sqrt(variance(values)) / m
    end

    def mean(values)
      values.sum(0.0) / values.size
    end

    # Variância populacional (÷ n): dispersão da amostra observada, não estimador.
    def variance(values)
      m = mean(values)
      values.sum(0.0) { |v| (v - m)**2 } / values.size
    end

    def median(values)
      sorted = values.map { |v| v.is_a?(BigDecimal) ? v : v.to_d }.sort
      n = sorted.size
      mid = n / 2
      n.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end

    # ---- Conciliação (aprendizado) ----------------------------------------------

    # Primeira RECOMPRA REAL do alvo após a âncora. Exige valor líquido > 0: uma
    # linha bonificada (brinde, net_value 0 — comum em distribuidora) NÃO confirma a
    # recompra, coerente com a geração, que ignora dia líquido ≤ 0 (predict).
    def confirming_invoice(pred)
      scope = Invoice.confirmed_only.sales.where(partner_id: @partner.id)
                     .where("negotiation_date > ?", pred.last_purchase_on)
                     .where("total_value > 0").order(:negotiation_date)
      case pred.level
      when "customer" then scope.first
      when "category" then scope.where(id: category_item_invoice_ids(pred.category_external_code)).first
      when "product"  then scope.where(id: paid_item_invoice_ids(product_id: pred.product_id)).first
      end
    end

    def overdue_missed?(pred, as_of)
      return false if pred.expected_date.nil?
      return false unless pred.expected_date + tolerance(pred.interval_days.to_i) < as_of

      !covered_by_open_order?(pred)
    end

    # Tolerância de atraso proporcional ao ciclo, limitada a [15, 90] dias.
    def tolerance(interval_days)
      interval_days.clamp(MIN_TOLERANCE, MAX_TOLERANCE)
    end

    def covered_by_open_order?(pred)
      case pred.level
      when "customer" then open_orders.exists?
      when "category" then open_order_category_codes.include?(pred.category_external_code)
      when "product"  then open_order_product_ids.include?(pred.product_id)
      end
    end

    # ---- Escopos e memoização ---------------------------------------------------

    def open_orders
      @open_orders ||= Order.portfolio.where(partner_id: @partner.id)
    end

    def open_order_product_ids
      @open_order_product_ids ||= OrderItem.where(order_id: open_orders.select(:id)).distinct.pluck(:product_id).compact
    end

    def open_order_category_codes
      @open_order_category_codes ||= Product.where(id: open_order_product_ids).distinct.pluck(:category_external_code).compact
    end

    # Itens de VENDA do parceiro com produto cadastrado (INNER JOIN products).
    def sale_items
      InvoiceItem.joins(:invoice).joins("INNER JOIN products ON products.id = invoice_items.product_id")
                 .where(invoices: { partner_id: @partner.id, confirmed: true, kind: Invoice.kinds[:sale] })
    end

    # invoice_ids com um item PAGO (net_value > 0) da categoria — brinde não conta.
    def category_item_invoice_ids(code)
      InvoiceItem.joins("INNER JOIN products ON products.id = invoice_items.product_id")
                 .where(products: { category_external_code: code }).where("invoice_items.net_value > 0")
                 .select(:invoice_id)
    end

    # invoice_ids com um item PAGO (net_value > 0) do produto — brinde não conta.
    def paid_item_invoice_ids(product_id:)
      InvoiceItem.where(product_id: product_id).where("net_value > 0").select(:invoice_id)
    end

    # ---- Montagem ---------------------------------------------------------------

    def base_prediction(level, target_key, stats)
      { level: level, target_key: target_key, **stats }
    end

    # A previsão aberta ainda reflete o cálculo atual? (âncora + data esperada +
    # intervalo). Se algo mudou, a antiga é superada.
    def unchanged?(existing, pred)
      existing.last_purchase_on == pred[:last_purchase_on] &&
        existing.expected_date == pred[:expected_date] &&
        existing.interval_days == pred[:interval_days]
    end

    # Mantém só as previsões mais relevantes por nível (mais ciclos, depois maior
    # confiança) — evita inundar a carteira com SKUs esporádicos.
    def top(predictions)
      predictions.sort_by { |p| [ -p[:cycles], -p[:confidence] ] }.first(MAX_ITEM_PREDICTIONS)
    end

    def persist_attributes(pred)
      {
        partner_id: @partner.id, level: pred[:level], target_key: pred[:target_key],
        product_id: pred[:product_id], category_external_code: pred[:category_external_code],
        category_name: pred[:category_name], last_purchase_on: pred[:last_purchase_on],
        expected_date: pred[:expected_date], expected_value: pred[:expected_value],
        expected_quantity: pred[:expected_quantity], confidence: pred[:confidence],
        interval_days: pred[:interval_days], cycles: pred[:cycles],
        method: METHOD, engine_version: VERSION, components: pred[:components], status: :open
      }
    end
  end
end
