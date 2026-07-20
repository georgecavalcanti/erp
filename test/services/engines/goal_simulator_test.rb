require "test_helper"

module Engines
  # Simulador de meta (doc 05.5) — heurística gulosa por valor esperado.
  class GoalSimulatorTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @sp = Salesperson.create!(external_code: 20_001, nickname: "VEND")
      @uid = 20_000
    end

    def wallet_partner
      p = Partner.create!(external_code: (@uid += 1), name: "P#{@uid}", active: true)
      Wallet.create!(salesperson: @sp, partner: p, starts_on: AS_OF - 1.year)
      p
    end

    def sale(partner, value, date: AS_OF - 20)
      @uid += 1
      Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: value,
                      kind: :sale, confirmed: true, partner: partner, salesperson: @sp, margin_value: value * 0.3)
    end

    def overdue_pred(partner, value:, conf: 80)
      RepurchasePrediction.create!(partner: partner, level: :customer, target_key: "customer",
                                   status: :open, last_purchase_on: AS_OF - 40, expected_date: AS_OF - 10,
                                   expected_value: value, interval_days: 30, confidence: conf, method: "t", engine_version: "t")
    end

    test "seleciona oportunidades por valor esperado até cobrir o gap" do
      Goal.create!(salesperson: @sp, period: AS_OF, kind: :revenue, amount: 20_000)
      sale(wallet_partner, 5_000, date: AS_OF - 3) # realizado 5k no mês → gap 15k
      3.times do
        p = wallet_partner
        sale(p, 12_000)
        overdue_pred(p, value: 10_000, conf: 90) # valor esperado ~9k cada
      end

      sim = Engines::GoalSimulator.new(@sp, as_of: AS_OF).call
      assert_operator sim[:gap], :>, 0
      assert sim[:covers_gap], "2 oportunidades de ~9k deveriam cobrir 15k"
      assert_operator sim[:count], :<=, 2 # menor conjunto (não seleciona todas)
      assert sim[:by_origin].key?("recompra")
    end

    test "sinaliza quando as oportunidades não cobrem o gap" do
      Goal.create!(salesperson: @sp, period: AS_OF, kind: :revenue, amount: 500_000)
      p = wallet_partner
      sale(p, 3_000)
      overdue_pred(p, value: 1_000, conf: 50)
      sim = Engines::GoalSimulator.new(@sp, as_of: AS_OF).call
      assert_not sim[:covers_gap]
    end

    test "sem meta: devolve as melhores oportunidades até a capacidade" do
      config = PrioritySetting.new(PrioritySetting::DEFAULTS.merge(daily_capacity: 2))
      4.times do
        p = wallet_partner
        sale(p, 8_000)
        overdue_pred(p, value: 5_000)
      end
      sim = Engines::GoalSimulator.new(@sp, as_of: AS_OF, config: config).call
      assert_nil sim[:gap]
      assert sim[:covers_gap] # sem gap, "cobre" por definição
      assert_operator sim[:count], :<=, 2 # respeita a capacidade
    end
  end
end
