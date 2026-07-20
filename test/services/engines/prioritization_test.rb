require "test_helper"

module Engines
  # Priorização (doc 05.4) — score, restrições, capacidade, estratégia, isolamento.
  class PrioritizationTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @sp = Salesperson.create!(external_code: 30_001, nickname: "VEND")
      @uid = 30_000
    end

    def partner_in_wallet(sp: @sp, **attrs)
      p = Partner.create!({ external_code: (@uid += 1), name: "P#{@uid}", active: true }.merge(attrs))
      Wallet.create!(salesperson: sp, partner: p, starts_on: AS_OF - 1.year)
      p
    end

    def sale(partner, value, date: AS_OF - 20)
      @uid += 1
      Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: value,
                      kind: :sale, confirmed: true, partner: partner, salesperson: @sp, margin_value: value * 0.3)
    end

    def overdue_pred(partner, value:, count: 1)
      count.times do |i|
        RepurchasePrediction.create!(partner: partner, level: :product, target_key: "product:#{@uid += 1}",
                                     status: :open, last_purchase_on: AS_OF - 40, expected_date: AS_OF - 10,
                                     expected_value: value, interval_days: 30, confidence: 60, method: "t", engine_version: "t")
      end
    end

    def plan = Engines::Prioritization.new(@sp, as_of: AS_OF).call

    test "cliente com recompra atrasada e alto potencial fica no topo" do
      big = partner_in_wallet
      sale(big, 10_000)
      overdue_pred(big, value: 5_000, count: 3)
      small = partner_in_wallet
      sale(small, 500)

      ranked = plan
      assert_equal big.id, ranked.first[:partner_id]
      assert ranked.first[:score] > ranked.last[:score]
      assert(ranked.first[:reasons].any? { |r| r[:key] == "recompra_atrasada" })
    end

    test "restrições são exibidas e rebaixam o score" do
      blocked = partner_in_wallet(blocked: true)
      sale(blocked, 10_000)
      overdue_pred(blocked, value: 5_000, count: 3)
      clean = partner_in_wallet
      sale(clean, 10_000)
      overdue_pred(clean, value: 5_000, count: 3)

      by_id = plan.index_by { |it| it[:partner_id] }
      assert(by_id[blocked.id][:restrictions].any? { |r| r[:key] == "bloqueio" })
      # mesmo potencial, mas o bloqueado pontua menos (penalidade)
      assert_operator by_id[blocked.id][:score], :<, by_id[clean.id][:score]
    end

    test "pedido em aberto vira restrição" do
      p = partner_in_wallet
      sale(p, 5_000)
      Order.create!(external_uid: (@uid += 1), total_value: 500, status: :pending, partner: p, salesperson: @sp)
      item = plan.find { |it| it[:partner_id] == p.id }
      assert(item[:restrictions].any? { |r| r[:key] == "pedido_aberto" })
    end

    test "persist! respeita a capacidade diária (nº de recommendations)" do
      config = PrioritySetting.new(PrioritySetting::DEFAULTS.merge(daily_capacity: 2))
      5.times { |i| p = partner_in_wallet; sale(p, (i + 1) * 1_000); overdue_pred(p, value: 1_000) }

      Engines::Prioritization.new(@sp, as_of: AS_OF, config: config).persist!
      assert_equal 5, Priority.for_date(AS_OF).where(salesperson: @sp).count       # pontua todos
      assert_equal 2, Recommendation.for_date(AS_OF).where(salesperson: @sp).count  # plano = capacidade
    end

    test "persist! é idempotente por dia e preserva recommendations já tocadas" do
      config = PrioritySetting.new(PrioritySetting::DEFAULTS.merge(daily_capacity: 3))
      3.times { |i| p = partner_in_wallet; sale(p, (i + 1) * 1_000) }
      Engines::Prioritization.new(@sp, as_of: AS_OF, config: config).persist!
      rec = Recommendation.for_date(AS_OF).where(salesperson: @sp).first
      rec.update!(status: :done)

      Engines::Prioritization.new(@sp, as_of: AS_OF, config: config).persist! # roda de novo
      assert_equal 3, Recommendation.for_date(AS_OF).where(salesperson: @sp).count # não duplica
      assert_predicate rec.reload, :status_done? # preservada
    end

    def cfg(capacity)
      PrioritySetting.new(PrioritySetting::DEFAULTS.merge(daily_capacity: capacity))
    end

    test "persist!: poda pendentes fora do top-N mas preserva as já tocadas" do
      5.times { |i| p = partner_in_wallet; sale(p, (i + 1) * 1_000); overdue_pred(p, value: (i + 1) * 1_000) }
      Engines::Prioritization.new(@sp, as_of: AS_OF, config: cfg(5)).persist!
      # a recomendação de MENOR prioridade (posição 5), marcada como tocada
      touched = Recommendation.for_date(AS_OF).where(salesperson: @sp).joins(:priority).order("priorities.position desc").first
      touched.update!(status: :accepted)

      # capacidade cai para 2 → pendentes fora do top-2 são podadas, a tocada fica
      Engines::Prioritization.new(@sp, as_of: AS_OF, config: cfg(2)).persist!
      recs = Recommendation.for_date(AS_OF).where(salesperson: @sp)
      assert_equal 2, recs.where(status: :pending).count
      assert recs.exists?(id: touched.id), "recomendação tocada não pode ser podada"
    end

    test "isolamento: só pontua clientes da carteira do próprio vendedor" do
      mine = partner_in_wallet
      sale(mine, 5_000)
      other_sp = Salesperson.create!(external_code: 30_999, nickname: "OUTRO")
      theirs = partner_in_wallet(sp: other_sp)
      sale(theirs, 50_000)

      ids = plan.map { |it| it[:partner_id] }
      assert_includes ids, mine.id
      assert_not_includes ids, theirs.id
    end

    test "estratégia acima da meta prioriza margem/risco (pesos deslocados)" do
      Goal.create!(salesperson: @sp, period: AS_OF, kind: :revenue, amount: 1_000)
      sale(partner_in_wallet, 100_000, date: AS_OF - 5) # realizado no mês >> meta → acima da meta
      w = Engines::Prioritization.new(@sp, as_of: AS_OF).send(:adjusted_weights)
      base = PrioritySetting.current.normalized_weights
      assert_operator w[:margin], :>, base[:margin]  # margem ganha peso acima da meta
      assert_operator w[:risk], :>, base[:risk]
    end
  end
end
