require "test_helper"

# Isolamento do Cliente 360 / Minha Carteira / atividades: o vendedor só abre e
# age sobre clientes da SUA carteira; nunca os de outra.
class Customer360Test < ActionDispatch::IntegrationTest
  setup do
    @sp_a = Salesperson.create!(external_code: 6001, nickname: "VEND.A")
    @sp_b = Salesperson.create!(external_code: 6002, nickname: "VEND.B")
    @pa = Partner.create!(external_code: 6101, name: "CLIENTE A")
    @pb = Partner.create!(external_code: 6102, name: "CLIENTE B")
    Wallet.create!(salesperson: @sp_a, partner: @pa, responsibility_type: :owner)
    Wallet.create!(salesperson: @sp_b, partner: @pb, responsibility_type: :owner)
    Invoice.create!(external_uid: 6201, negotiation_date: Date.current, total_value: 1000, kind: :sale, salesperson: @sp_a, partner: @pa)
    Invoice.create!(external_uid: 6202, negotiation_date: Date.current, total_value: 2000, kind: :sale, salesperson: @sp_b, partner: @pb)
    @vend_a = User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a)
    @admin  = User.create!(email_address: "adm@x.com", password: "secret123", role: :administrador)
  end

  test "vendedor abre o 360 de cliente da sua carteira" do
    sign_in_as(@vend_a)
    get cliente_path(@pa)

    assert_inertia_component "Customer360"
    assert_equal "CLIENTE A", inertia.props[:identification][:name]
    assert_in_delta 1000, inertia.props[:summary][:revenue_total], 0.01
  end

  test "vendedor NÃO abre o 360 de cliente de outra carteira (isolamento)" do
    sign_in_as(@vend_a)
    get cliente_path(@pb)

    assert_redirected_to wallet_path
    assert_match(/fora da sua carteira/i, flash[:alert])
  end

  test "admin abre o 360 de qualquer cliente" do
    sign_in_as(@admin)
    get cliente_path(@pb)

    assert_inertia_component "Customer360"
    assert_equal "CLIENTE B", inertia.props[:identification][:name]
  end

  test "vendedor registra atividade em cliente da carteira" do
    sign_in_as(@vend_a)
    assert_difference -> { Activity.count }, 1 do
      post atividades_path, params: { partner_id: @pa.id, kind: "visit", notes: "Visita de rotina" }
    end
    a = Activity.last
    assert_equal @pa.id, a.partner_id
    assert_equal @vend_a.id, a.user_id
    assert_equal @sp_a.id, a.salesperson_id
    assert a.kind_visit?
    assert_redirected_to cliente_path(@pa)
  end

  test "vendedor NÃO registra atividade em cliente de outra carteira" do
    sign_in_as(@vend_a)
    assert_no_difference -> { Activity.count } do
      post atividades_path, params: { partner_id: @pb.id, kind: "visit", notes: "x" }
    end
    assert_match(/fora da sua carteira/i, flash[:alert])
  end

  test "Minha carteira lista só os clientes da carteira do vendedor" do
    sign_in_as(@vend_a)
    get wallet_path

    assert_inertia_component "Wallet"
    assert_equal [ "CLIENTE A" ], inertia.props[:clients].map { |c| c[:name] }
    assert_equal 0.0, inertia.props[:clients].first[:days_since] # compra hoje → ativo
    assert_equal "ativo", inertia.props[:clients].first[:segment]
  end

  test "Minha carteira do admin vê clientes de todas as carteiras" do
    sign_in_as(@admin)
    get wallet_path

    names = inertia.props[:clients].map { |c| c[:name] }
    assert_includes names, "CLIENTE A"
    assert_includes names, "CLIENTE B"
  end
end
