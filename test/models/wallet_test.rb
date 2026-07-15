require "test_helper"

class WalletTest < ActiveSupport::TestCase
  setup do
    @sp = Salesperson.create!(external_code: 7001, nickname: "S")
    @sp2 = Salesperson.create!(external_code: 7002, nickname: "S2")
    @p = Partner.create!(external_code: 7101, name: "P")
  end

  test "active traz só as carteiras vigentes (ends_on nil)" do
    ativa = Wallet.create!(salesperson: @sp, partner: @p)
    Wallet.create!(salesperson: @sp2, partner: @p, starts_on: Date.current - 30, ends_on: Date.current - 1)

    assert_equal [ ativa.id ], Wallet.active.pluck(:id)
  end

  test "um parceiro só tem uma carteira vigente" do
    Wallet.create!(salesperson: @sp, partner: @p)
    dup = Wallet.new(salesperson: @sp2, partner: @p)

    assert_not dup.valid?
    assert dup.errors[:partner_id].any?
  end

  test "close! encerra a vigência e some do active" do
    w = Wallet.create!(salesperson: @sp, partner: @p)
    w.close!

    assert_not_nil w.ends_on
    assert_not Wallet.active.exists?(w.id)
  end

  test "transferência: fecha a antiga e abre a nova sem violar o índice único" do
    Wallet.create!(salesperson: @sp, partner: @p).close!
    nova = Wallet.create!(salesperson: @sp2, partner: @p)

    assert nova.persisted?
    assert_equal @sp2.id, Wallet.active.find_by(partner: @p).salesperson_id
  end

  test "ends_on anterior a starts_on é inválido" do
    w = Wallet.new(salesperson: @sp, partner: @p, starts_on: Date.current, ends_on: Date.current - 1)

    assert_not w.valid?
    assert w.errors[:ends_on].any?
  end
end
