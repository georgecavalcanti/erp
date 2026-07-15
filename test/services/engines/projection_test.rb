require "test_helper"

module Engines
  class ProjectionTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 15) # quarta; julho/2026 = 23 dias úteis (11 decorridos, 12 restantes)

    setup do
      @sp = Salesperson.create!(external_code: 4001, nickname: "VEND")
      # Realizado líquido = 100.000 (venda) − 10.000 (devolução) = 90.000; margem 30.000 − 3.000 = 27.000
      Invoice.create!(external_uid: 4101, negotiation_date: Date.new(2026, 7, 5), total_value: 100_000,
                      kind: :sale, salesperson: @sp, margin_value: 30_000)
      Invoice.create!(external_uid: 4102, negotiation_date: Date.new(2026, 7, 6), total_value: 10_000,
                      kind: :return, salesperson: @sp, margin_value: 3_000)
      # Carteira a faturar = 50.000
      Order.create!(external_uid: 4201, total_value: 50_000, status: :pending, salesperson: @sp)
      # Meta de faturamento = 200.000
      Goal.create!(salesperson: @sp, period: AS_OF, kind: :revenue, amount: 200_000)
    end

    def result
      @result ||= Engines::Projection.new(@sp, as_of: AS_OF).call
    end

    test "dias úteis do mês" do
      assert_equal({ total: 23, elapsed: 11, remaining: 12 }, result[:business_days])
    end

    test "realizado líquido e margem com sinal de devolução" do
      assert_in_delta 90_000, result[:realized], 0.01
      assert_in_delta 27_000, result[:realized_margin], 0.01
    end

    test "cenário conservador = realizado + 80% da carteira (sem run-rate)" do
      # 90.000 + 50.000×0,80 = 130.000
      assert_in_delta 130_000, result[:scenarios][:conservative][:value], 0.01
      assert_equal 90, result[:scenarios][:conservative][:confidence]
    end

    test "cenários são monotônicos: conservador ≤ provável ≤ potencial" do
      c = result[:scenarios][:conservative][:value]
      l = result[:scenarios][:likely][:value]
      p = result[:scenarios][:potential][:value]
      assert_operator c, :<=, l
      assert_operator l, :<=, p
    end

    test "provável inclui run-rate dos dias restantes" do
      # run_rate = 90.000/11×12 = 98.181,82; provável = 90.000 + 45.000 + 98.181,82×0,5
      assert_in_delta 184_090.91, result[:scenarios][:likely][:value], 1.0
      # margem projetada = valor × taxa de margem realizada (27.000/90.000 = 0,3)
      assert_in_delta 55_227.27, result[:scenarios][:likely][:margin_value], 1.0
    end

    test "gap, atingimento esperado, atingimento realizado e ritmo diário" do
      assert_in_delta 15_909.09, result[:scenarios][:likely][:gap], 1.0      # 200.000 − provável
      assert_in_delta 95_652.17, result[:expected_to_date], 1.0             # 200.000 × 11/23
      assert_in_delta 45.0, result[:attainment_percent], 0.1                # 90.000/200.000
      assert_in_delta 9_166.67, result[:daily_rhythm_needed], 0.1           # (200.000−90.000)/12
    end

    test "componentes rastreáveis por cenário (MVP 5)" do
      keys = result[:scenarios][:likely][:components].map { |c| c[:key] }
      assert_equal %w[realizado carteira tendencia], keys
      # conservador não tem tendência (peso 0)
      assert_equal %w[realizado carteira], result[:scenarios][:conservative][:components].map { |c| c[:key] }
    end

    test "meta já atingida zera o ritmo necessário" do
      Goal.for_period(AS_OF).where(salesperson: @sp).update_all(amount: 50_000) # < realizado
      r = Engines::Projection.new(@sp, as_of: AS_OF).call
      assert_equal 0, r[:daily_rhythm_needed]
    end

    test "sem meta: gap/atingimento/ritmo ficam nulos" do
      Goal.where(salesperson: @sp).delete_all
      r = Engines::Projection.new(@sp, as_of: AS_OF).call
      assert_nil r[:target]
      assert_nil r[:attainment_percent]
      assert_nil r[:daily_rhythm_needed]
      assert_nil r[:scenarios][:likely][:gap]
    end

    test "só conta o próprio vendedor (isolamento)" do
      other = Salesperson.create!(external_code: 4002, nickname: "OUTRO")
      Invoice.create!(external_uid: 4999, negotiation_date: Date.new(2026, 7, 7), total_value: 500_000,
                      kind: :sale, salesperson: other)
      assert_in_delta 90_000, result[:realized], 0.01 # inalterado
    end

    test "persist! grava a leva append-only (3 cenários)" do
      assert_difference -> { ::Projection.count }, 3 do
        Engines::Projection.new(@sp, as_of: AS_OF).persist!
      end
      row = ::Projection.scenario_likely.last
      assert_equal @sp.id, row.salesperson_id
      assert_in_delta 200_000, row.target_value, 0.01
      assert_in_delta 90_000, row.realized_value, 0.01
      assert row.components["parcels"].present?
    end
  end
end
