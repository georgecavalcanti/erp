require "test_helper"

module Engines
  class ConsumptionDropTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @partner = Partner.create!(external_code: 80_001, name: "CONSUMO LTDA")
      @uid = 80_000
    end

    def sale(partner, date, value, kind: :sale)
      @uid += 1
      Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: value,
                      kind: kind, confirmed: true, partner: partner)
    end

    def result(partner = @partner)
      Engines::ConsumptionDrop.new(partner, as_of: AS_OF).call
    end

    test "queda de consumo: recente bem abaixo do baseline → trend :drop" do
      # baseline total 40.000 em 360d → 10.000 por janela de 90d; recente 5.000.
      sale(@partner, Date.new(2025, 10, 1), 40_000)
      sale(@partner, Date.new(2026, 6, 1), 5_000)
      r = result

      assert_in_delta 10_000, r[:baseline_net], 1.0
      assert_in_delta 5_000, r[:recent_net], 1.0
      assert_in_delta 50.0, r[:drop_percent], 0.5
      assert_equal :drop, r[:trend]
    end

    test "expansão: recente acima do baseline → trend :growth" do
      sale(@partner, Date.new(2025, 10, 1), 40_000) # baseline 90d = 10.000
      sale(@partner, Date.new(2026, 6, 1), 15_000)
      assert_equal :growth, result[:trend]
    end

    test "estável: recente próximo do baseline → trend :stable" do
      sale(@partner, Date.new(2025, 10, 1), 40_000) # baseline 90d = 10.000
      sale(@partner, Date.new(2026, 6, 1), 9_000)
      assert_equal :stable, result[:trend]
    end

    test "sem base histórica: só compra recente → trend :growth e drop nulo" do
      sale(@partner, Date.new(2026, 6, 1), 5_000)
      r = result
      assert_equal :growth, r[:trend]
      assert_nil r[:drop_percent]
    end

    test "devolução recente entra líquida (reduz o recente)" do
      sale(@partner, Date.new(2025, 10, 1), 40_000)  # baseline 90d = 10.000
      sale(@partner, Date.new(2026, 6, 1), 8_000)
      sale(@partner, Date.new(2026, 6, 10), 6_000, kind: :return) # líquido recente = 2.000
      r = result
      assert_in_delta 2_000, r[:recent_net], 1.0
      assert_equal :drop, r[:trend]
    end

    test "lote: classifica vários parceiros de uma vez" do
      other = Partner.create!(external_code: 80_002, name: "OUTRO")
      sale(@partner, Date.new(2026, 6, 1), 5_000)
      sale(other, Date.new(2026, 6, 1), 9_000)
      map = Engines::ConsumptionDrop.for_partners([ @partner.id, other.id ], as_of: AS_OF)
      assert_equal 2, map.size
      assert map.key?(@partner.id)
      assert map.key?(other.id)
    end
  end
end
