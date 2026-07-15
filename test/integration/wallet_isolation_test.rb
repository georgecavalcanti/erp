require "test_helper"

# Teste OBRIGATÓRIO de isolamento de carteira (doc 07 / plano Sprint 3):
# o vendedor A nunca enxerga dados do vendedor B — em NENHUMA tela e nem
# forçando o filtro de vendedor do cliente. O escopo é sempre imposto pelo
# perfil (AccessPolicy), nunca pelo parâmetro que chega.
class WalletIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @co = Company.find_or_create_by!(external_code: 1) { |c| c.name = "JATTO" }
    @sp_a = Salesperson.create!(external_code: 9001, nickname: "VEND.A")
    @sp_b = Salesperson.create!(external_code: 9002, nickname: "VEND.B")
    @pa = Partner.create!(external_code: 9101, name: "CLIENTE A")
    @pb = Partner.create!(external_code: 9102, name: "CLIENTE B")

    # Faturamento: A = 1000, B = 2000
    Invoice.create!(external_uid: 9201, negotiation_date: Date.current, total_value: 1000, kind: :sale,
                    salesperson: @sp_a, partner: @pa, company: @co)
    Invoice.create!(external_uid: 9202, negotiation_date: Date.current, total_value: 2000, kind: :sale,
                    salesperson: @sp_b, partner: @pb, company: @co)
    # Carteira a faturar
    PendingOrder.create!(external_uid: 9301, salesperson: @sp_a, partner: @pa, total_value: 500)
    PendingOrder.create!(external_uid: 9302, salesperson: @sp_b, partner: @pb, total_value: 700)
    # Inadimplência
    OverdueTitle.create!(salesperson: @sp_a, partner: @pa, salesperson_label: "VEND.A", amount: 300, category: :open)
    OverdueTitle.create!(salesperson: @sp_b, partner: @pb, salesperson_label: "VEND.B", amount: 400, category: :open)
    # Carteiras (wallets) + logins
    Wallet.create!(salesperson: @sp_a, partner: @pa, responsibility_type: :owner)
    Wallet.create!(salesperson: @sp_b, partner: @pb, responsibility_type: :owner)
    @vend_a = User.create!(email_address: "a@jatto.local", password: "secret123", role: :vendedor, salesperson: @sp_a)
    @admin  = User.create!(email_address: "adm@jatto.local", password: "secret123", role: :administrador)
  end

  test "Dashboard: vendedor A vê só o próprio faturamento e ranking" do
    sign_in_as(@vend_a)
    get root_path

    assert_inertia_component "Dashboard"
    assert_equal 1000.0, inertia.props[:summary][:net_revenue]
    assert_equal [ "VEND.A" ], inertia.props[:topSalespeople].map { |r| r[:name] }
    partners = inertia.props[:topPartners].map { |r| r[:name] }
    assert_includes partners, "CLIENTE A"
    assert_not_includes partners, "CLIENTE B"
  end

  test "Dashboard: admin vê todos os vendedores" do
    sign_in_as(@admin)
    get root_path

    assert_equal 3000.0, inertia.props[:summary][:net_revenue]
    assert_equal 2, inertia.props[:topSalespeople].size
  end

  test "elevação de privilégio: A forçando salesperson_ids=B não vê B" do
    sign_in_as(@vend_a)
    get root_path(salesperson_ids: [ @sp_b.id ])

    # A∩B = vazio: o filtro do cliente jamais amplia o escopo autorizado.
    assert_equal 0.0, inertia.props[:summary][:net_revenue]
    assert_empty inertia.props[:topSalespeople]
  end

  test "Situação geral: só a linha do próprio vendedor" do
    sign_in_as(@vend_a)
    get situation_path

    assert_inertia_component "Situation"
    assert_equal [ "VEND.A" ], inertia.props[:rows].map { |r| r[:name] }
    assert_equal 1000.0, inertia.props[:totals][:liquido]
    assert_equal 500.0, inertia.props[:totals][:carteira]
    assert_equal 300.0, inertia.props[:totals][:inad_aberto]
  end

  test "Carteira: só os pendentes do próprio vendedor" do
    sign_in_as(@vend_a)
    get portfolio_path

    assert_inertia_component "Portfolio"
    assert_equal 500.0, inertia.props[:summary][:total]
    assert_equal [ "VEND.A" ], inertia.props[:bySalesperson].map { |r| r[:name] }
  end

  test "Inadimplência: só os títulos do próprio vendedor" do
    sign_in_as(@vend_a)
    get receivables_path

    assert_inertia_component "Receivables"
    assert_equal 300.0, inertia.props[:summary][:open_total]
  end

  test "Vendedores e Parceiros: rankings só com os dados do próprio vendedor" do
    sign_in_as(@vend_a)

    get salespeople_path
    assert_equal [ "VEND.A" ], inertia.props[:ranking].map { |r| r[:name] }

    get partners_path
    assert_equal [ "CLIENTE A" ], inertia.props[:ranking].map { |r| r[:name] }
  end

  test "Dropdown de filtros do vendedor lista só ele e seus clientes" do
    sign_in_as(@vend_a)
    get root_path

    opts = inertia.props[:filterOptions]
    assert_equal [ "VEND.A" ], opts[:salespeople].map { |o| o[:name] }
    assert_equal [ "CLIENTE A" ], opts[:partners].map { |o| o[:name] }
  end
end
