require "test_helper"

class RepurchaseForecastJobTest < ActiveJob::TestCase
  def sale(partner, date, value, uid)
    Invoice.create!(external_uid: uid, negotiation_date: date, total_value: value,
                    kind: :sale, confirmed: true, partner: partner)
  end

  # Parceiro com cadência regular e uma carteira vigente (tem dono).
  def owned_partner_with_history(code, base: Date.new(2025, 12, 8))
    sp = Salesperson.create!(external_code: code, nickname: "V#{code}")
    partner = Partner.create!(external_code: code, name: "P#{code}")
    Wallet.create!(salesperson: sp, partner: partner, starts_on: base)
    7.times { |i| sale(partner, base + (i * 30), 1_000, (code * 100) + i) }
    partner
  end

  test "gera previsões só para parceiros com carteira vigente" do
    owned = owned_partner_with_history(70_001)
    orphan = Partner.create!(external_code: 70_099, name: "SEM DONO")
    7.times { |i| sale(orphan, Date.new(2025, 12, 8) + (i * 30), 1_000, 70_099_00 + i) }

    stats = RepurchaseForecastJob.new.perform
    assert_operator stats[:created], :>=, 1
    assert_operator RepurchasePrediction.where(partner_id: owned.id).count, :>=, 1
    assert_equal 0, RepurchasePrediction.where(partner_id: orphan.id).count
  end

  test "roda em lote sem duplicar (idempotente entre execuções)" do
    owned_partner_with_history(70_002)
    RepurchaseForecastJob.new.perform
    before = RepurchasePrediction.status_open.count
    RepurchaseForecastJob.new.perform # mesma âncora → nada novo
    assert_equal before, RepurchasePrediction.status_open.count
  end

  test "concilia antes de gerar: compra nova confirma a previsão anterior" do
    partner = owned_partner_with_history(70_003)
    RepurchaseForecastJob.new.perform
    anchor = RepurchasePrediction.status_open.find_by(partner_id: partner.id, target_key: "customer").last_purchase_on

    sale(partner, anchor + 29, 1_200, 70_003_99) # comprou de novo
    stats = RepurchaseForecastJob.new.perform

    assert_operator stats[:confirmed], :>=, 1
    assert RepurchasePrediction.exists?(partner_id: partner.id, target_key: "customer", status: :confirmed)
    # e uma nova aberta com a âncora atualizada
    fresh = RepurchasePrediction.status_open.find_by(partner_id: partner.id, target_key: "customer")
    assert_equal anchor + 29, fresh.last_purchase_on
  end

  test "escopo por partner_id processa só aquele parceiro" do
    a = owned_partner_with_history(70_004)
    b = owned_partner_with_history(70_005)
    RepurchaseForecastJob.new.perform(a.id)

    assert_operator RepurchasePrediction.where(partner_id: a.id).count, :>=, 1
    assert_equal 0, RepurchasePrediction.where(partner_id: b.id).count
  end
end
