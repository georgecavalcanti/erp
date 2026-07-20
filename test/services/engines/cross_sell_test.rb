require "test_helper"

module Engines
  # Expansão de mix (doc 05.3) — pares por UF + porte, dados sintéticos.
  class CrossSellTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 7, 16)

    setup do
      @uid = 40_000
      @cli = Partner.create!(external_code: 40_001, name: "CLIENTE", state: "SP", active: true)
    end

    def product(code, name)
      Product.create!(external_code: (@uid += 1), description: "P#{code}", category_external_code: code, category_name: name)
    end

    # Cria uma venda do parceiro com um item de `product` no valor `net`.
    def buy(partner, product, net, date: AS_OF - 1.month)
      @uid += 1
      inv = Invoice.create!(external_uid: @uid, negotiation_date: date, total_value: net,
                            kind: :sale, confirmed: true, partner: partner)
      InvoiceItem.create!(invoice: inv, product: product, external_sequence: 1, quantity: 1, net_value: net, gross_value: net)
    end

    def peer(code, state: "SP")
      Partner.create!(external_code: (@uid += 1), name: "PAR#{code}", state: state, active: true)
    end

    test "sugere categoria que os pares compram e o cliente não" do
      quimicos = product(100, "QUIMICOS")
      sacos = product(200, "SACOS")
      buy(@cli, quimicos, 10_000) # cliente compra QUIMICOS (receita base 10k)

      # 4 pares na mesma UF, porte parecido, todos compram SACOS (que o cliente não tem)
      4.times do |i|
        pr = peer(i)
        buy(pr, quimicos, 9_000 + (i * 200)) # porte parecido
        buy(pr, sacos, 2_000 + (i * 100))    # categoria ausente no cliente
      end

      res = Engines::CrossSell.new(@cli, as_of: AS_OF).call
      sacos_opp = res.find { |c| c[:category_external_code] == 200 }
      assert sacos_opp, "esperava SACOS como oportunidade"
      assert_equal 4, sacos_opp[:peers_buying]
      assert_in_delta 2_150, sacos_opp[:potential_value], 1.0 # mediana de [2000,2100,2200,2300]
    end

    test "não sugere categoria que o cliente já compra" do
      quimicos = product(100, "QUIMICOS")
      buy(@cli, quimicos, 10_000)
      4.times do |i|
        pr = peer(i)
        buy(pr, quimicos, 9_500 + (i * 100))
      end
      res = Engines::CrossSell.new(@cli, as_of: AS_OF).call
      assert_nil res.find { |c| c[:category_external_code] == 100 } # já compra
    end

    test "ignora pares de outra UF" do
      quimicos = product(100, "QUIMICOS")
      sacos = product(200, "SACOS")
      buy(@cli, quimicos, 10_000)
      4.times do |i|
        pr = peer(i, state: "RJ") # outra UF
        buy(pr, quimicos, 9_500)
        buy(pr, sacos, 3_000)
      end
      assert_empty Engines::CrossSell.new(@cli, as_of: AS_OF).call # sem pares na UF do cliente
    end

    test "exige um mínimo de pares comprando a categoria" do
      quimicos = product(100, "QUIMICOS")
      sacos = product(200, "SACOS")
      buy(@cli, quimicos, 10_000)
      # 4 pares de porte, mas só 2 compram SACOS (< MIN_PEERS_BUYING = 3)
      4.times do |i|
        pr = peer(i)
        buy(pr, quimicos, 9_500)
        buy(pr, sacos, 2_000) if i < 2
      end
      assert_nil Engines::CrossSell.new(@cli, as_of: AS_OF).call.find { |c| c[:category_external_code] == 200 }
    end
  end
end
