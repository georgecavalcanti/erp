require "test_helper"

module Engines
  # Previsão de recompra (doc 05.2) — históricos SINTÉTICOS determinísticos.
  class RepurchaseTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @partner = Partner.create!(external_code: 90_001, name: "REGULAR LTDA")
      @uid = 90_000
    end

    # Uma venda confirmada do parceiro em `date` por `value`.
    def sale(partner, date, value)
      @uid += 1
      Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: value,
                      kind: :sale, confirmed: true, partner: partner)
    end

    def customer_pred(partner = @partner, as_of: AS_OF)
      Engines::Repurchase.new(partner, as_of: as_of).call.find { |p| p[:level] == :customer }
    end

    # --- Nível cliente: cadência regular -------------------------------------

    test "cadência regular: data esperada = última compra + mediana do intervalo" do
      # 7 compras a cada 30 dias → mediana 30; última em 2026-06-06.
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      pred = customer_pred

      assert_equal :customer, pred[:level]
      assert_equal "customer", pred[:target_key]
      assert_equal 30, pred[:interval_days]
      assert_equal base + (6 * 30), pred[:last_purchase_on]
      assert_equal base + (6 * 30) + 30, pred[:expected_date]
      assert_equal 6, pred[:cycles]
    end

    test "cadência regular com muitos ciclos → confiança alta (teto 95)" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      # 6 intervalos (≥ saturação) + CV 0 → 100 truncado no teto 95.
      assert_equal 95, customer_pred[:confidence]
    end

    test "valor esperado = mediana do valor por compra" do
      base = Date.new(2025, 12, 8)
      values = [ 1_000, 1_200, 800, 1_100, 900, 1_000, 1_050 ]
      values.each_with_index { |v, i| sale(@partner, base + (i * 30), v) }
      # mediana de [800,900,1000,1000,1050,1100,1200] = 1000
      assert_in_delta 1_000, customer_pred[:expected_value], 0.01
    end

    # --- Nível cliente: poucos ciclos ----------------------------------------

    test "poucos ciclos (2 compras) → prevê, mas confiança baixa" do
      sale(@partner, Date.new(2026, 5, 1), 1_000)
      sale(@partner, Date.new(2026, 5, 31), 1_000) # 1 intervalo de 30
      pred = customer_pred

      assert_equal 30, pred[:interval_days]
      assert_equal 1, pred[:cycles]
      assert_equal 17, pred[:confidence] # 100 × (1/6) × 1,0
    end

    test "1 compra só → sem previsão (não há intervalo)" do
      sale(@partner, Date.new(2026, 6, 1), 1_000)
      assert_nil customer_pred
    end

    # --- Nível cliente: irregular --------------------------------------------

    test "intervalos irregulares → confiança menor que a de cadência regular" do
      # Intervalos [10,60,15,90,20] → mediana 20; CV alto derruba a regularidade.
      base = Date.new(2026, 1, 1)
      offsets = [ 0, 10, 70, 85, 175, 195 ]
      offsets.each { |o| sale(@partner, base + o, 1_000) }
      pred = customer_pred

      assert_equal 20, pred[:interval_days]
      assert_equal 5, pred[:cycles]
      assert_equal 46, pred[:confidence] # 100 × (5/6) × 1/(1+0,796)
      assert_operator pred[:confidence], :<, 95
    end

    test "cadência sazonal (trimestral regular) → intervalo ~90 e boa regularidade" do
      base = Date.new(2024, 7, 1)
      8.times { |i| sale(@partner, base + (i * 90), 5_000) } # ~trimestral, 7 ciclos
      pred = customer_pred

      assert_equal 90, pred[:interval_days]
      assert_equal 7, pred[:cycles]
      assert_equal 95, pred[:confidence] # regular, muitos ciclos
    end

    # --- Regra do pedido aberto ----------------------------------------------

    test "não prevê no nível cliente se há pedido aberto (já está no pipeline)" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      Order.create!(external_uid: 91_000, total_value: 500, status: :pending, partner: @partner)

      assert_nil customer_pred
    end

    # --- Níveis categoria e produto ------------------------------------------

    def product_with_category(code: 1_001, name: "Categoria 1", desc: "PROD X")
      Product.create!(external_code: @uid += 1, description: desc,
                      category_external_code: code, category_name: name)
    end

    # Adiciona um item de venda (produto) a uma nota do parceiro na data.
    def item_sale(partner, date, product, net:, qty:)
      inv = sale(partner, date, net)
      InvoiceItem.create!(invoice: inv, product: product, external_sequence: 1,
                          quantity: qty, net_value: net, gross_value: net)
      inv
    end

    test "nível produto: previsão por SKU com quantidade esperada" do
      prod = product_with_category
      base = Date.new(2025, 12, 1)
      4.times { |i| item_sale(@partner, base + (i * 20), prod, net: 300, qty: 10) }
      pred = Engines::Repurchase.new(@partner, as_of: AS_OF).call.find { |p| p[:level] == :product }

      assert_equal "product:#{prod.id}", pred[:target_key]
      assert_equal prod.id, pred[:product_id]
      assert_equal 20, pred[:interval_days]
      assert_in_delta 10, pred[:expected_quantity], 0.01
    end

    test "nível categoria: agrega os produtos do grupo" do
      p1 = product_with_category(code: 9_009, name: "Grupo 9", desc: "A")
      p2 = product_with_category(code: 9_009, name: "Grupo 9", desc: "B")
      base = Date.new(2025, 12, 1)
      # 4 datas; em cada uma um item do grupo 9009 (produtos alternados).
      [ p1, p2, p1, p2 ].each_with_index { |pr, i| item_sale(@partner, base + (i * 25), pr, net: 200, qty: 5) }
      pred = Engines::Repurchase.new(@partner, as_of: AS_OF).call.find { |p| p[:level] == :category && p[:category_external_code] == 9_009 }

      assert pred, "esperava previsão de categoria 9009"
      assert_equal 25, pred[:interval_days]
      assert_equal "Grupo 9", pred[:category_name]
    end

    test "produto/categoria: exige ≥3 compras (poucos ciclos não geram item)" do
      prod = product_with_category
      base = Date.new(2026, 4, 1)
      2.times { |i| item_sale(@partner, base + (i * 20), prod, net: 300, qty: 10) } # só 2 compras
      preds = Engines::Repurchase.new(@partner, as_of: AS_OF).call
      assert_nil preds.find { |p| p[:level] == :product }
    end

    # --- Persistência (idempotência e superação) -----------------------------

    test "persist! grava as abertas e é idempotente (não duplica)" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }

      first = Engines::Repurchase.new(@partner, as_of: AS_OF).persist!
      assert_operator first.size, :>=, 1
      assert_no_difference -> { RepurchasePrediction.status_open.count } do
        Engines::Repurchase.new(@partner, as_of: AS_OF).persist! # mesma âncora → nada muda
      end
    end

    test "persist! supera a aberta quando a âncora muda (nova compra)" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      Engines::Repurchase.new(@partner, as_of: AS_OF).persist!
      original = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: "customer")

      sale(@partner, base + (7 * 30), 1_000) # nova compra move a âncora
      Engines::Repurchase.new(@partner, as_of: AS_OF).persist!

      assert_predicate original.reload, :status_canceled?
      current = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: "customer")
      assert_equal base + (7 * 30), current.last_purchase_on
    end

    # --- Conciliação: open → confirmed / missed ------------------------------

    test "reconcile!: compra real após a âncora → confirmed + confirmed_invoice_id" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      Engines::Repurchase.new(@partner, as_of: AS_OF).persist!
      anchor = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: "customer").last_purchase_on

      buy = sale(@partner, anchor + 28, 1_500) # comprou de novo
      res = Engines::Repurchase.new(@partner).reconcile!(as_of: anchor + 30)

      assert_equal 1, res[:confirmed]
      pred = RepurchasePrediction.find_by(partner_id: @partner.id, target_key: "customer", status: :confirmed)
      assert_equal buy.id, pred.confirmed_invoice_id
      assert_equal buy.negotiation_date, pred.actual_date
    end

    test "reconcile!: venceu sem compra nem pedido → missed" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      Engines::Repurchase.new(@partner, as_of: AS_OF).persist!
      pred = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: "customer")

      # muito depois da data esperada + carência, sem nova compra
      res = Engines::Repurchase.new(@partner).reconcile!(as_of: pred.expected_date + 60)

      assert_equal 1, res[:missed]
      assert_predicate pred.reload, :status_missed?
    end

    test "reconcile!: dentro da carência não marca missed" do
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      Engines::Repurchase.new(@partner, as_of: AS_OF).persist!
      pred = RepurchasePrediction.status_open.find_by(partner_id: @partner.id, target_key: "customer")

      res = Engines::Repurchase.new(@partner).reconcile!(as_of: pred.expected_date + 5) # < carência (15)
      assert_equal 0, res[:missed]
      assert_predicate pred.reload, :status_open?
    end

    # --- Isolamento ----------------------------------------------------------

    test "o motor lê só o histórico do próprio parceiro" do
      other = Partner.create!(external_code: 90_002, name: "OUTRO")
      base = Date.new(2025, 12, 8)
      7.times { |i| sale(@partner, base + (i * 30), 1_000) }
      # ruído do outro parceiro, cadência bem diferente
      3.times { |i| sale(other, base + (i * 7), 50_000) }

      pred = customer_pred
      assert_equal 30, pred[:interval_days] # inalterado pelo outro parceiro
      assert_equal 1_000, pred[:expected_value]
    end
  end
end
