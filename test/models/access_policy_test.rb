require "test_helper"

class AccessPolicyTest < ActiveSupport::TestCase
  setup do
    @sp_a = Salesperson.create!(external_code: 8001, nickname: "A")
    @sp_b = Salesperson.create!(external_code: 8002, nickname: "B")
    @pa = Partner.create!(external_code: 8101, name: "PA")
    @pb = Partner.create!(external_code: 8102, name: "PB")
    Wallet.create!(salesperson: @sp_a, partner: @pa, responsibility_type: :owner)
    Wallet.create!(salesperson: @sp_b, partner: @pb, responsibility_type: :owner)
  end

  test "gestor, admin e diretoria são irrestritos (nil)" do
    %i[gestor_comercial administrador diretoria].each do |role|
      pol = AccessPolicy.new(User.new(email_address: "#{role}@x.com", role: role))
      assert pol.unrestricted?, "#{role} deveria ser irrestrito"
      assert_nil pol.authorized_salesperson_ids
      assert_nil pol.authorized_partner_ids
    end
  end

  test "vendedor vê só o próprio vendedor e sua carteira" do
    pol = AccessPolicy.new(User.new(email_address: "v@x.com", role: :vendedor, salesperson: @sp_a))

    assert_not pol.unrestricted?
    assert_equal [ @sp_a.id ], pol.authorized_salesperson_ids
    assert_equal [ @pa.id ], pol.authorized_partner_ids
  end

  test "vendedor sem vínculo não vê nada (fail-closed)" do
    pol = AccessPolicy.new(User.new(email_address: "v2@x.com", role: :vendedor))

    assert_equal [], pol.authorized_salesperson_ids
    assert_equal [], pol.authorized_partner_ids
  end

  test "coordenador vê a equipe (subordinados) mais o próprio" do
    coord = User.create!(email_address: "c@x.com", password: "secret123", role: :coordenador)
    User.create!(email_address: "sub@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a, manager: coord)

    pol = AccessPolicy.new(coord)
    assert_equal [ @sp_a.id ], pol.authorized_salesperson_ids
    assert_equal [ @pa.id ], pol.authorized_partner_ids
  end

  test "carteira encerrada não conta para authorized_partner_ids" do
    u = User.new(email_address: "v@x.com", role: :vendedor, salesperson: @sp_a)
    Wallet.where(salesperson: @sp_a).find_each(&:close!)

    assert_equal [], AccessPolicy.new(u).authorized_partner_ids
  end
end
