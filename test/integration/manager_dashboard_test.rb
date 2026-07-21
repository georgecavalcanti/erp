require "test_helper"

# Barreira de papel do Dashboard do Gestor (/gestor) + o recorte por equipe.
class ManagerDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @sp_a = Salesperson.create!(external_code: 9301, nickname: "ANA")
    @sp_c = Salesperson.create!(external_code: 9303, nickname: "CARLA")
    Goal.create!(salesperson: @sp_a, period: Date.current, kind: :revenue, amount: 100_000)
    Goal.create!(salesperson: @sp_c, period: Date.current, kind: :revenue, amount: 100_000)
    Invoice.create!(external_uid: 9401, negotiation_date: Date.current, total_value: 40_000, kind: :sale, salesperson: @sp_a)
    Invoice.create!(external_uid: 9403, negotiation_date: Date.current, total_value: 30_000, kind: :sale, salesperson: @sp_c)

    @coord = User.create!(email_address: "coord@x.com", password: "secret123", role: :coordenador)
    # Subordinado do coordenador vinculado a ANA — define a equipe = [sp_a].
    User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a, manager: @coord)
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
    @diretoria = User.create!(email_address: "d@x.com", password: "secret123", role: :diretoria)
    # Vendedor avulso (com o PRÓPRIO vendedor — salesperson_id é único por usuário).
    sp_v = Salesperson.create!(external_code: 9309, nickname: "VÍTOR")
    @vendedor = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: sp_v)
  end

  test "vendedor não acessa o dashboard do gestor" do
    sign_in_as(@vendedor)
    get manager_path
    assert_redirected_to root_path
  end

  test "coordenador vê só a sua equipe" do
    sign_in_as(@coord)
    get manager_path

    assert_inertia_component "ManagerDashboard"
    names = inertia.props[:rows].map { |r| r[:name] }
    assert_equal ["ANA"], names # CARLA está fora da equipe
  end

  test "gestor vê todos os vendedores com atividade" do
    sign_in_as(@gestor)
    get manager_path

    names = inertia.props[:rows].map { |r| r[:name] }
    assert_includes names, "ANA"
    assert_includes names, "CARLA"
    assert_not inertia.props[:readonly]
  end

  test "diretoria acessa em modo somente leitura" do
    sign_in_as(@diretoria)
    get manager_path

    assert_inertia_component "ManagerDashboard"
    assert inertia.props[:readonly]
  end
end
