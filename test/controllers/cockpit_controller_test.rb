require "test_helper"

class CockpitControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sp = Salesperson.create!(external_code: 3001, nickname: "VEND")
    Invoice.create!(external_uid: 3101, negotiation_date: Date.current, total_value: 50_000, kind: :sale, salesperson: @sp)
    Goal.create!(salesperson: @sp, period: Date.current, kind: :revenue, amount: 100_000)
    @vend = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
  end

  test "vendedor vê o cockpit com meta, realizado e cenários" do
    sign_in_as(@vend)
    get cockpit_path

    assert_inertia_component "Cockpit"
    proj = inertia.props[:projection]
    assert_equal 100_000.0, proj[:target]
    assert_equal 50_000.0, proj[:realized]
    assert_operator proj[:scenarios][:conservative][:value], :<=, proj[:scenarios][:potential][:value]
    assert_equal @sp.nickname, inertia.props[:salesperson][:name]
  end

  test "cockpit reflete só o próprio vendedor (isolamento)" do
    other = Salesperson.create!(external_code: 3002, nickname: "OUTRO")
    Invoice.create!(external_uid: 3999, negotiation_date: Date.current, total_value: 999_000, kind: :sale, salesperson: other)
    sign_in_as(@vend)

    get cockpit_path
    assert_equal 50_000.0, inertia.props[:projection][:realized] # não enxerga os 999k de OUTRO
  end

  test "usuário sem vínculo com vendedor vê estado vazio" do
    admin = User.create!(email_address: "a@x.com", password: "secret123", role: :administrador)
    sign_in_as(admin)

    get cockpit_path
    assert_inertia_component "Cockpit"
    assert_nil inertia.props[:projection]
    assert_nil inertia.props[:salesperson]
  end

  test "root redireciona vendedor para o cockpit" do
    sign_in_as(@vend)
    get root_path
    assert_redirected_to cockpit_path
  end

  test "root do gestor continua no dashboard consolidado" do
    sign_in_as(@gestor)
    get root_path
    assert_inertia_component "Dashboard"
  end
end
