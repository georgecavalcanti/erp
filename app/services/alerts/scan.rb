module Alerts
  # Varredura de alertas operacionais (doc 09.14.2). Reavalia todas as condições e
  # sincroniza a tabela `alerts`: cria os novos, atualiza os que seguem ocorrendo e
  # RESOLVE os que deixaram de ocorrer. Como cada varredura recomputa o quadro
  # completo, qualquer alerta aberto cuja chave não está mais disparando é resolvido.
  #
  # Grupos: integração (sync atrasado/falho — usa sync_runs), dados (cadastro
  # incompleto), conciliação (divergência local nota × itens), negócio (meta ausente,
  # projeção crítica). Local e determinístico; não bate no ERP.
  #
  #   Alerts::Scan.call            # roda a varredura (via Alerts::ScanJob/rake)
  class Scan
    SYNC_STALE_MINUTES = 70    # 2× o intervalo de 30min + folga (doc 09)
    PROJECTION_CRITICAL = 0.60 # projeção provável < 60% da meta = crítica
    RECON_TOLERANCE = 1.0      # R$ de tolerância entre total da nota e Σ itens
    RECON_LOOKBACK_DAYS = 90
    BUSINESS_TZ = "America/Sao_Paulo".freeze

    def self.call(as_of: Time.current)
      new(as_of).call
    end

    def initialize(as_of = Time.current)
      @as_of = as_of
    end

    def call
      findings = integration + data + reconciliation + business
      sync!(findings)
    end

    private

    # ---- Sincronização do quadro de alertas -------------------------------------

    def sync!(findings)
      keys = findings.map { |f| f[:key] }
      stats = { created: 0, updated: 0, resolved: 0, firing: keys.size }
      Alert.transaction do
        findings.each do |f|
          alert = Alert.open.find_or_initialize_by(key: f[:key])
          if alert.new_record?
            alert.assign_attributes(f.merge(first_detected_at: @as_of, last_detected_at: @as_of))
            alert.save!
            stats[:created] += 1
          else
            alert.update!(f.except(:key).merge(last_detected_at: @as_of))
            stats[:updated] += 1
          end
        end
        stats[:resolved] = Alert.open.where.not(key: keys).update_all(resolved_at: @as_of)
      end
      stats
    end

    def finding(area, severity, key, title, message, metadata: {}, entity: nil)
      {
        area: area, severity: severity, key: key, title: title, message: message, metadata: metadata,
        entity_type: entity&.class&.name, entity_id: entity&.id
      }
    end

    # ---- Integração (sync atrasado/falho) ---------------------------------------

    def integration
      findings = []
      last = SyncRun.recent.first

      # Atraso só é avaliado em horário comercial (à noite não há sync agendado).
      if business_hours?
        if last.nil?
          findings << finding(:integration, :high, "sync_missing", "Sincronização nunca executada",
                              "Nenhuma execução registrada em sync_runs.")
        elsif last.finished_at < @as_of - SYNC_STALE_MINUTES.minutes
          mins = ((@as_of - last.finished_at) / 60).round
          findings << finding(:integration, :high, "sync_late", "Sincronização atrasada",
                              "Última sincronização há #{mins} min (esperado ≤ #{SYNC_STALE_MINUTES}).",
                              metadata: { last_run_at: last.finished_at.iso8601, minutes: mins })
        end
      end

      if last && last.status != "ok"
        detail = Array(last.error_messages).first.to_s.presence || "Última sincronização terminou com falha parcial."
        findings << finding(:integration, :high, "sync_failed", "Falha na última sincronização", detail,
                            metadata: { status: last.status })
      end
      findings
    end

    # ---- Dados (cadastro incompleto) --------------------------------------------

    def data
      findings = []
      no_seller = Partner.active.where(id: Invoice.confirmed_only.sales.select(:partner_id))
                         .where.not(id: Wallet.active.select(:partner_id)).count
      if no_seller.positive?
        findings << finding(:data, :medium, "data_partners_no_seller", "Clientes sem vendedor",
                            "#{no_seller} cliente(s) ativo(s) com compras e sem carteira vigente.",
                            metadata: { count: no_seller })
      end

      no_category = Product.where(active: true, category_external_code: [ nil, 0 ]).count
      if no_category.positive?
        findings << finding(:data, :low, "data_products_no_category", "Produtos sem categoria",
                            "#{no_category} produto(s) ativo(s) sem grupo.", metadata: { count: no_category })
      end

      no_cost = Product.where(active: true).where("current_cost IS NULL OR current_cost = 0").count
      if no_cost.positive?
        findings << finding(:data, :low, "data_products_no_cost", "Produtos sem custo",
                            "#{no_cost} produto(s) ativo(s) sem custo atual.", metadata: { count: no_cost })
      end
      findings
    end

    # ---- Conciliação (integridade local nota × itens) ---------------------------

    def reconciliation
      since = @as_of.to_date - RECON_LOOKBACK_DAYS
      divergent = Invoice.confirmed_only.where("negotiation_date >= ?", since).where.not(items_synced_at: nil)
                         .joins("JOIN (SELECT invoice_id, SUM(net_value) s FROM invoice_items GROUP BY invoice_id) it ON it.invoice_id = invoices.id")
                         .where("ABS(invoices.total_value - it.s) > ?", RECON_TOLERANCE).count
      return [] if divergent.zero?

      [ finding(:reconciliation, :medium, "recon_invoice_items_mismatch", "Divergência nota × itens",
                "#{divergent} nota(s) dos últimos #{RECON_LOOKBACK_DAYS}d com total ≠ Σ dos itens.",
                metadata: { count: divergent, tolerance: RECON_TOLERANCE }) ]
    end

    # ---- Negócio (meta ausente, projeção crítica) -------------------------------

    def business
      period = @as_of.to_date.beginning_of_month
      active_seller_ids = Salesperson.active
                                     .where(id: User.where(active: true).where.not(salesperson_id: nil).select(:salesperson_id))
                                     .pluck(:id)
      return [] if active_seller_ids.empty?

      no_goal_ids = active_seller_ids - Goal.for_period(period).where(salesperson_id: active_seller_ids).distinct.pluck(:salesperson_id)
      findings = Salesperson.where(id: no_goal_ids).map do |sp|
        finding(:business, :medium, "seller_no_goal:#{sp.id}", "Vendedor sem meta",
                "#{sp.nickname} sem meta de faturamento em #{period.strftime('%m/%Y')}.", entity: sp)
      end
      findings + critical_projections(period, active_seller_ids - no_goal_ids)
    end

    # Projeção provável (a mais recente do mês) abaixo de PROJECTION_CRITICAL da meta.
    def critical_projections(period, seller_ids)
      return [] if seller_ids.empty?

      latest = Projection.scenario_likely.for_period(period).where(salesperson_id: seller_ids)
                         .select("DISTINCT ON (salesperson_id) *").order(:salesperson_id, created_at: :desc)
      latest.filter_map do |proj|
        target = proj.target_value.to_d
        next if target <= 0 || proj.value.to_d >= target * PROJECTION_CRITICAL

        sp = proj.salesperson
        pct = (proj.value.to_d / target * 100).round
        finding(:business, :high, "projection_critical:#{sp.id}", "Projeção crítica",
                "#{sp.nickname}: provável em #{pct}% da meta de #{period.strftime('%m/%Y')}.",
                metadata: { percent: pct }, entity: sp)
      end
    end

    def business_hours?
      t = @as_of.in_time_zone(BUSINESS_TZ)
      (1..5).cover?(t.wday) && (8...19).cover?(t.hour)
    end
  end
end
