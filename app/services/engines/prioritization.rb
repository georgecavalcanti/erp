module Engines
  # Motor de priorização (doc 05.4). Para um vendedor, pontua os clientes da SUA
  # carteira e monta o plano do dia (top-N pela capacidade). Determinístico, local,
  # consome os sinais da Sprint 6 (recompra, risco, queda).
  #
  #   score = Σ peso_fator × fator(0..1)   (pesos configuráveis em PrioritySetting)
  #   fatores: potencial de receita, probabilidade, urgência, contribuição p/ gap,
  #            risco de perda, margem, relevância estratégica (doc 05.4)
  #
  # Estratégia ADAPTATIVA por posição vs meta (ajusta os pesos):
  #   abaixo da meta  → potencial/conversão/urgência/gap
  #   próximo da meta → gap + conversão (menor conjunto que fecha o gap)
  #   acima/atingida  → margem/risco(retenção)/estratégico
  #
  # Restrições (doc 05.4) são SEMPRE exibidas e REBAIXAM o score (bloqueio,
  # inadimplência, pedido aberto, contato recente, margem baixa).
  #
  # O ESCOPO por vendedor é a própria carteira (Wallet.active) — não vaza cliente
  # de outra carteira.
  class Prioritization
    VERSION = "mvp-1".freeze
    METHOD = "score-ponderado-adaptativo".freeze

    NEAR_GOAL = 0.10          # gap ≤ 10% da meta = "próximo da meta"
    RISK_SCORE = { "em_risco" => 1.0, "inativo" => 0.85, "em_atencao" => 0.6,
                   "novo_em_ativacao" => 0.4, "em_expansao" => 0.25, "saudavel" => 0.15 }.freeze
    RESTRICTION_PENALTY = { "bloqueio" => 0.4, "inadimplencia" => 0.5, "pedido_aberto" => 0.6,
                            "contato_recente" => 0.7, "margem_baixa" => 0.7 }.freeze

    def initialize(salesperson, as_of: Date.current, config: PrioritySetting.current)
      @salesperson = salesperson
      @as_of = as_of
      @config = config
    end

    # Lista de itens de prioridade, ordenada (position 1 = mais prioritário). Sem persistir.
    def call
      ids = wallet_partner_ids
      return [] if ids.empty?

      load_signals(ids)
      weights = adjusted_weights

      items = ids.map { |pid| build_item(pid, weights) }
      ranked = items.sort_by { |it| -it[:score] }
      ranked.each_with_index { |it, i| it[:position] = i + 1 }
      ranked
    end

    # Grava o plano do dia (snapshot). Idempotente e seguro sob concorrência:
    #   * advisory lock por (vendedor, dia) serializa regenerações simultâneas;
    #   * PODA as recomendações PENDENTES que saíram do top-N (o plano não cresce
    #     além da capacidade nem mantém cliente que caiu da carteira) — preserva as
    #     que o vendedor já tocou (aceita/adiada/concluída/descartada = histórico);
    #   * RELIGA as remanescentes às novas priorities e cria as do top-N que faltam.
    def persist!(limit: @config.daily_capacity)
      ranked = call
      top = ranked.first(limit)
      top_ids = top.map { |it| it[:partner_id] }.to_set
      Priority.transaction do
        lock_salesperson_day!

        # Poda: pendentes fora do novo top-N não seguem no plano.
        Recommendation.for_date(@as_of).where(salesperson_id: @salesperson.id, status: :pending)
                      .where.not(partner_id: top_ids.to_a).delete_all

        recs = Recommendation.for_date(@as_of).where(salesperson_id: @salesperson.id).to_a
        Recommendation.where(id: recs.map(&:id)).update_all(priority_id: nil) # solta a FK antes de trocar
        Priority.for_date(@as_of).where(salesperson_id: @salesperson.id).delete_all
        Priority.insert_all(ranked.map { |it| priority_attributes(it) }) if ranked.any?

        by_partner = Priority.for_date(@as_of).where(salesperson_id: @salesperson.id).index_by(&:partner_id)
        recs.each { |rec| Recommendation.where(id: rec.id).update_all(priority_id: by_partner[rec.partner_id]&.id) }

        existing = recs.map(&:partner_id).to_set
        top.reject { |it| existing.include?(it[:partner_id]) }
           .each { |it| create_recommendation(it, by_partner[it[:partner_id]]) }
      end
      top
    end

    # Lock de transação por (vendedor, dia): duas regenerações simultâneas do mesmo
    # plano não se atropelam (auto-liberado no commit/rollback).
    def lock_salesperson_day!
      key = (@salesperson.id.to_i << 20) ^ @as_of.strftime("%Y%m%d").to_i
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{key})")
    end

    private

    # ---- Escopo (carteira do vendedor) -----------------------------------------

    def wallet_partner_ids
      @wallet_partner_ids ||= Wallet.active.where(salesperson_id: @salesperson.id).distinct.pluck(:partner_id)
    end

    # ---- Sinais em lote (sem N+1) ----------------------------------------------

    def load_signals(ids)
      @risk = Engines::Risk.classify_many(ids, as_of: @as_of)
      @revenue = net_12m(ids)
      @margin = margin_pct(ids)
      @overdue = RepurchasePrediction.overdue(@as_of).where(partner_id: ids)
                                     .group(:partner_id).pluck(Arel.sql("partner_id, COUNT(*), COALESCE(SUM(expected_value),0), COALESCE(AVG(confidence),0)"))
                                     .to_h { |pid, c, sum, conf| [ pid, { count: c, sum: sum.to_f, conf: conf.to_f } ] }
      @blocked = Partner.where(id: ids, blocked: true).pluck(:id).to_set
      @open_order_ids = Order.portfolio.where(partner_id: ids).distinct.pluck(:partner_id).to_set
      @overdue_title_ids = OverdueTitle.where(partner_id: ids).where.not(amount: 0).distinct.pluck(:partner_id).to_set
      @last_contact = Activity.where(partner_id: ids).group(:partner_id).maximum(:occurred_at)
      @max_potential = ids.map { |pid| raw_potential(pid) }.max.to_f
      @max_revenue = @revenue.values.max.to_f
    end

    # ---- Item de prioridade -----------------------------------------------------

    def build_item(pid, weights)
      factors = score_factors(pid)
      restrictions = restrictions_for(pid)
      base = weights.sum { |k, w| w * factors[k][:value] }
      penalty = restrictions.map { |r| RESTRICTION_PENALTY[r[:key]] || 1.0 }.min || 1.0
      reasons = reasons_for(pid)
      {
        partner_id: pid, score: (base * penalty * 100).round(2), score_factors: factors,
        reasons: reasons, potential_value: raw_potential(pid).round(2), urgency: (factors[:urgency][:value] * 100).round,
        restrictions: restrictions, suggested_action: action_for(reasons)
      }
    end

    # Cada fator em 0..1, com o peso normalizado aplicado guardado para auditoria.
    def score_factors(pid)
      raw = {
        revenue: normalize(raw_potential(pid), @max_potential),
        conversion: conversion_factor(pid),
        urgency: urgency_factor(pid),
        gap: gap_factor(pid),
        risk: RISK_SCORE[status(pid)] || 0.2,
        margin: [ (@margin[pid] || 0) / 40.0, 1.0 ].min,
        strategic: normalize(@revenue[pid] || 0, @max_revenue)
      }
      raw.transform_values { |v| { value: v.round(4) } }
    end

    # Potencial em R$: recompras atrasadas somadas, ou o ritmo mensal do cliente.
    def raw_potential(pid)
      od = @overdue[pid]
      monthly = (@revenue[pid] || 0.0) / 12.0
      [ od ? od[:sum] : 0.0, monthly ].max
    end

    def conversion_factor(pid)
      od = @overdue[pid]
      return (od[:conf] / 100.0).clamp(0.1, 0.95) if od && od[:conf].positive?

      status(pid) == "em_expansao" ? 0.6 : 0.4
    end

    def urgency_factor(pid)
      od = @overdue[pid]
      days = @risk.dig(pid, :days_since_purchase)
      u = 0.0
      u += [ (od[:count] * 0.25), 0.6 ].min if od          # recompra atrasada pesa
      u += 0.4 if days && days > 90                          # sem comprar há muito
      u += 0.2 if %w[em_risco inativo].include?(status(pid))
      u.clamp(0.0, 1.0)
    end

    def gap_factor(pid)
      return 0.0 unless gap&.positive?

      [ raw_potential(pid) / gap, 1.0 ].min
    end

    # ---- Motivos e restrições ---------------------------------------------------

    def reasons_for(pid)
      reasons = []
      od = @overdue[pid]
      reasons << reason("recompra_atrasada", "#{od[:count]} recompra(s) atrasada(s)") if od
      (@risk.dig(pid, :signals) || []).each do |s|
        reasons << reason(s[:key], s[:label]) if %w[queda_consumo inadimplencia sem_contato].include?(s[:key])
      end
      reasons << reason("risco", "Cliente #{@risk.dig(pid, :status_label)}") if %w[em_risco inativo].include?(status(pid))
      reasons.uniq { |r| r[:key] }
    end

    def restrictions_for(pid)
      r = []
      r << restriction("bloqueio", "Cadastro bloqueado") if @blocked.include?(pid)
      r << restriction("inadimplencia", "Inadimplência aberta") if @overdue_title_ids.include?(pid)
      r << restriction("pedido_aberto", "Já tem pedido em aberto") if @open_order_ids.include?(pid)
      if (lc = @last_contact[pid]) && (@as_of.to_date - lc.to_date).to_i <= @config.recent_contact_days
        r << restriction("contato_recente", "Contato há ≤ #{@config.recent_contact_days}d")
      end
      if @config.min_margin_percent && (@margin[pid] || 0) < @config.min_margin_percent
        r << restriction("margem_baixa", "Margem abaixo da política")
      end
      r
    end

    def action_for(reasons)
      key = reasons.first&.dig(:key)
      case key
      when "recompra_atrasada" then "Ligar sobre a recompra prevista"
      when "queda_consumo", "risco" then "Retomar contato — cliente em risco"
      when "inadimplencia" then "Tratar pendência financeira"
      else "Contato de relacionamento"
      end
    end

    # ---- Estratégia adaptativa (pesos por posição vs meta) ----------------------

    def adjusted_weights
      base = @config.normalized_weights
      mult = strategy_multipliers
      adj = base.to_h { |k, w| [ k, w * mult[k] ] }
      total = adj.values.sum
      total.zero? ? adj : adj.transform_values { |w| w / total }
    end

    def strategy_multipliers
      case strategy
      when :near_goal  then { revenue: 1.0, conversion: 1.4, urgency: 1.0, gap: 1.6, risk: 0.8, margin: 0.9, strategic: 0.7 }
      when :above_goal then { revenue: 0.8, conversion: 0.9, urgency: 0.8, gap: 0.5, risk: 1.5, margin: 1.6, strategic: 1.4 }
      else                  { revenue: 1.3, conversion: 1.2, urgency: 1.2, gap: 1.2, risk: 1.0, margin: 0.9, strategic: 0.8 } # below/no goal
      end
    end

    def strategy
      return :below_goal unless target&.positive?
      return :above_goal if gap.to_f <= 0
      return :near_goal if gap <= target * NEAR_GOAL

      :below_goal
    end

    # ---- Meta / realizado do vendedor (lazy — não dependem de load_signals) -----

    def target
      return @target if defined?(@target)

      @target = Goal.for_period(@as_of).find_by(salesperson_id: @salesperson.id, kind: :revenue)&.amount
    end

    def gap
      return @gap if defined?(@gap)

      @gap = seller_gap
    end

    def seller_gap
      return nil unless target

      realized = (Invoice.confirmed_only.sales.where(salesperson_id: @salesperson.id).for_month(@as_of).sum(:total_value) -
                  Invoice.confirmed_only.returns.where(salesperson_id: @salesperson.id).for_month(@as_of).sum(:total_value)).to_d
      (target - realized)
    end

    # ---- Persistência -----------------------------------------------------------

    def priority_attributes(it)
      now = Time.current
      {
        salesperson_id: @salesperson.id, partner_id: it[:partner_id], reference_date: @as_of,
        score: it[:score], score_factors: it[:score_factors], reasons: it[:reasons],
        potential_value: it[:potential_value], urgency: it[:urgency], suggested_action: it[:suggested_action],
        restrictions: it[:restrictions], position: it[:position], valid_until: @as_of,
        method: METHOD, engine_version: VERSION, created_at: now, updated_at: now
      }
    end

    # Cria a recommendation determinística de um item do top-N (channel padrão: ligação).
    def create_recommendation(it, priority)
      Recommendation.create!(
        salesperson_id: @salesperson.id, partner_id: it[:partner_id],
        priority_id: priority&.id, reference_date: @as_of,
        diagnosis: it[:reasons].map { |r| r[:label] }.join(" · ").presence || "Oportunidade de relacionamento",
        recommendation: it[:suggested_action], next_action: it[:suggested_action],
        evidences: it[:reasons], potential_impact: { revenue: it[:potential_value] },
        restrictions: it[:restrictions], confidence: (it.dig(:score_factors, :conversion, :value).to_f * 100).round,
        channel: :call, status: :pending
      )
    end

    # ---- Agregações auxiliares --------------------------------------------------

    def status(pid) = @risk.dig(pid, :status).to_s

    def normalize(value, max)
      return 0.0 if max.to_f <= 0

      (value.to_f / max).clamp(0.0, 1.0)
    end

    def net_12m(ids)
      range = (@as_of - 12.months)..@as_of
      sales = Invoice.confirmed_only.sales.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      returns = Invoice.confirmed_only.returns.where(partner_id: ids, negotiation_date: range).group(:partner_id).sum(:total_value)
      net = Hash.new(0.0)
      sales.each { |pid, v| net[pid] += v.to_f }
      returns.each { |pid, v| net[pid] -= v.to_f }
      net
    end

    # Margem % líquida (12m) por parceiro.
    def margin_pct(ids)
      range = (@as_of - 12.months)..@as_of
      base = Invoice.confirmed_only.where(partner_id: ids, negotiation_date: range)
      sales_net = base.sales.group(:partner_id).sum(:total_value)
      sales_mgn = base.sales.group(:partner_id).sum(:margin_value)
      ret_net = base.returns.group(:partner_id).sum(:total_value)
      ret_mgn = base.returns.group(:partner_id).sum(:margin_value)
      ids.index_with do |pid|
        net = (sales_net[pid].to_d - ret_net[pid].to_d)
        mgn = (sales_mgn[pid].to_d - ret_mgn[pid].to_d)
        net.positive? ? (mgn / net * 100).to_f.round(2) : 0.0
      end
    end

    def reason(key, label) = { key: key, label: label }
    def restriction(key, label) = { key: key, label: label }
  end
end
