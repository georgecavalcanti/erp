require "test_helper"

class Customer360ReportTest < ActiveSupport::TestCase
  AS_OF = Date.new(2026, 7, 15)

  setup do
    @sp = Salesperson.create!(external_code: 7101, nickname: "VEND")
    @partner = Partner.create!(external_code: 7201, name: "CLIENTE X", city: "PALMAS", state: "TO",
                               segment: "Supermercado", blocked: false)
    Wallet.create!(salesperson: @sp, partner: @partner, responsibility_type: :owner)
    @pa = Product.create!(external_code: 7301, description: "PAPEL TOALHA", category_name: "PAPEIS")
    @pb = Product.create!(external_code: 7302, description: "DETERGENTE", category_name: "QUIMICOS")

    # Venda julho 1000 (margem 300): 600 PAPEIS + 400 QUIMICOS
    inv1 = Invoice.create!(external_uid: 7401, negotiation_date: Date.new(2026, 7, 5), total_value: 1000,
                           kind: :sale, salesperson: @sp, partner: @partner, margin_value: 300)
    inv1.invoice_items.create!(external_sequence: 1, product: @pa, quantity: 1, gross_value: 600, net_value: 600)
    inv1.invoice_items.create!(external_sequence: 2, product: @pb, quantity: 1, gross_value: 400, net_value: 400)
    # Venda junho 500 (margem 150): 500 PAPEIS
    inv2 = Invoice.create!(external_uid: 7402, negotiation_date: Date.new(2026, 6, 10), total_value: 500,
                           kind: :sale, salesperson: @sp, partner: @partner, margin_value: 150)
    inv2.invoice_items.create!(external_sequence: 1, product: @pa, quantity: 1, gross_value: 500, net_value: 500)
    # Devolução julho 200 (margem 60)
    Invoice.create!(external_uid: 7403, negotiation_date: Date.new(2026, 7, 8), total_value: 200,
                    kind: :return, salesperson: @sp, partner: @partner, margin_value: 60)

    Order.create!(external_uid: 7501, total_value: 300, status: :pending, salesperson: @sp, partner: @partner)
    OverdueTitle.create!(partner: @partner, salesperson_label: "VEND", amount: 100, category: :open)
    OverdueTitle.create!(partner: @partner, salesperson_label: "VEND", amount: 50, category: :protested)
    u = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
    Activity.create!(user: u, partner: @partner, salesperson: @sp, kind: :contact, notes: "Ligação de rotina",
                     occurred_at: Time.new(2026, 7, 10, 10))

    @report = Customer360Report.new(@partner, as_of: AS_OF)
  end

  test "identificação inclui dono da carteira e bloqueio" do
    id = @report.identification
    assert_equal "CLIENTE X", id[:name]
    assert_equal "VEND", id[:salesperson]
    assert_equal "PALMAS", id[:city]
    assert_not id[:blocked]
  end

  test "summary: receita líquida, margem, ticket e frequência" do
    s = @report.summary
    assert_in_delta 1300, s[:revenue_total], 0.01   # 1000 + 500 − 200
    assert_in_delta 390, s[:margin_total], 0.01      # 300 + 150 − 60
    assert_in_delta 30.0, s[:margin_percent], 0.01   # 390/1300
    assert_equal 2, s[:invoice_count]                # 2 vendas
    assert_in_delta 750, s[:avg_ticket], 0.01        # 1500/2
    assert_equal Date.new(2026, 7, 5), s[:last_purchase_on]
    assert_equal 2, s[:purchases_12m]
    assert_equal 2, s[:active_months_12m]            # jun + jul
  end

  test "mix por categoria com participação" do
    mix = @report.mix_by_category
    papeis = mix.find { |m| m[:category] == "PAPEIS" }
    quimicos = mix.find { |m| m[:category] == "QUIMICOS" }
    assert_in_delta 1100, papeis[:revenue], 0.01     # 600 + 500
    assert_in_delta 73.3, papeis[:share], 0.1        # 1100/1500
    assert_in_delta 400, quimicos[:revenue], 0.01
  end

  test "evolução mensal preenche 12 meses com jun/jul corretos" do
    ev = @report.monthly_evolution
    assert_equal 12, ev.size
    jun = ev.find { |e| e[:month] == "2026-06" }
    jul = ev.find { |e| e[:month] == "2026-07" }
    assert_in_delta 500, jun[:net], 0.01
    assert_in_delta 800, jul[:net], 0.01             # 1000 − 200
  end

  test "financeiro: inadimplência aberta + protestada" do
    f = @report.financial
    assert_in_delta 100, f[:overdue_open], 0.01
    assert_in_delta 50, f[:overdue_protested], 0.01
    assert_in_delta 150, f[:overdue_total], 0.01
  end

  test "pedidos abertos e atividades recentes" do
    assert_equal 1, @report.open_orders.size
    assert_in_delta 300, @report.open_orders.first[:total_value], 0.01
    acts = @report.recent_activities
    assert_equal 1, acts.size
    assert_equal "contact", acts.first[:kind]
  end

  test "top_products traz o estoque disponível do snapshot" do
    @pa.create_stock_level!(on_hand: 100, reserved: 10, blocked: 0, synced_at: Time.current)
    papel = @report.top_products.find { |p| p[:product] == "PAPEL TOALHA" }

    assert_in_delta 90, papel[:available], 0.001 # 100 − 10
  end
end
