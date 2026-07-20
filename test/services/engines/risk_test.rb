require "test_helper"

module Engines
  # Classificação de risco da carteira (doc 05.3) — cenários determinísticos.
  class RiskTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @partner = Partner.create!(external_code: 60_001, name: "RISCO LTDA")
      @uid = 60_000
    end

    def sale(partner, date, value, kind: :sale)
      @uid += 1
      Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: value,
                      kind: kind, confirmed: true, partner: partner)
    end

    def overdue_prediction(partner)
      RepurchasePrediction.create!(partner: partner, level: :customer, target_key: "customer",
                                   status: :open, last_purchase_on: AS_OF - 40, expected_date: AS_OF - 10,
                                   interval_days: 30, confidence: 50, method: "t", engine_version: "t")
    end

    def status(partner = @partner)
      Engines::Risk.new(partner, as_of: AS_OF).call[:status]
    end

    def full(partner = @partner)
      Engines::Risk.new(partner, as_of: AS_OF).call
    end

    test "sem nenhuma compra → novo em ativação" do
      assert_equal :novo_em_ativacao, status
    end

    test "primeira compra recente e poucas compras → novo em ativação" do
      sale(@partner, AS_OF - 20, 3_000)
      sale(@partner, AS_OF - 10, 3_000)
      assert_equal :novo_em_ativacao, status
    end

    test "sem comprar há mais de 180 dias → inativo" do
      sale(@partner, AS_OF - 400, 5_000)
      sale(@partner, AS_OF - 300, 5_000)
      sale(@partner, AS_OF - 200, 5_000)
      assert_equal :inativo, status
    end

    test "inadimplência aberta → em risco" do
      sale(@partner, AS_OF - 400, 5_000)
      sale(@partner, AS_OF - 30, 5_000)
      OverdueTitle.create!(partner: @partner, salesperson_label: "X", amount: 1_200, category: :open)
      s = full
      assert_equal :em_risco, s[:status]
      assert(s[:signals].any? { |sig| sig[:key] == "inadimplencia" })
    end

    test "queda de consumo + recompra atrasada → em risco" do
      sale(@partner, Date.new(2025, 10, 1), 40_000) # baseline 90d = 10.000
      sale(@partner, AS_OF - 30, 2_000)             # recente 2.000 → queda
      overdue_prediction(@partner)
      assert_equal :em_risco, status
    end

    test "só recompra atrasada (consumo estável) → em atenção" do
      sale(@partner, Date.new(2025, 10, 1), 20_000) # baseline 90d = 5.000
      sale(@partner, AS_OF - 20, 5_000)             # recente 5.000 → estável
      overdue_prediction(@partner)
      s = full
      assert_equal :em_atencao, s[:status]
      assert(s[:signals].any? { |sig| sig[:key] == "recompra_atrasada" })
    end

    test "sem comprar entre 90 e 180 dias, sem outros sinais → em atenção" do
      sale(@partner, AS_OF - 500, 5_000)
      sale(@partner, AS_OF - 120, 5_000)
      assert_equal :em_atencao, status
    end

    test "consumo em alta → em expansão" do
      sale(@partner, Date.new(2025, 10, 1), 20_000) # baseline 90d = 5.000
      sale(@partner, AS_OF - 20, 12_000)            # recente 12.000 → crescimento
      s = full
      assert_equal :em_expansao, s[:status]
      assert(s[:signals].any? { |sig| sig[:key] == "expansao" })
    end

    test "comprador recente e estável, sem sinais → saudável" do
      # cadência mensal estável por ~15 meses → recente ≈ baseline
      15.times { |i| sale(@partner, AS_OF - (i * 30) - 5, 3_000) }
      assert_equal :saudavel, status
    end

    test "lote classifica vários parceiros isoladamente" do
      inativo = @partner
      sale(inativo, AS_OF - 200, 5_000)
      novo = Partner.create!(external_code: 60_002, name: "NOVO")
      sale(novo, AS_OF - 10, 1_000)

      map = Engines::Risk.classify_many([ inativo.id, novo.id ], as_of: AS_OF)
      assert_equal :inativo, map[inativo.id][:status]
      assert_equal :novo_em_ativacao, map[novo.id][:status]
    end
  end
end
