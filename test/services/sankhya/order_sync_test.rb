require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class OrderSyncTest < ActiveSupport::TestCase
    # Par (STATUSNOTA, PENDENTE) -> status, conforme mapa da Fase 0.
    PENDENTE = {
      "NUNOTA" => 125_072, "CODPARC" => 42, "CODVEND" => 7, "CODEMP" => 1,
      "DTNEG" => "2026-07-10", "DTMOV" => "2026-07-10", "VLRNOTA" => 193.64,
      "STATUSNOTA" => "L", "PENDENTE" => "S", "CIF_FOB" => "S",
      "NOMEPARC" => "CLIENTE X", "APELIDO" => "CARLA", "NOMEFANTASIA" => "JATTO"
    }.freeze
    AGUARDANDO = PENDENTE.merge("NUNOTA" => 125_073, "STATUSNOTA" => "A")
    FATURADO = PENDENTE.merge("NUNOTA" => 125_074, "PENDENTE" => "N")

    test "deriva status pending/awaiting/billed do par (STATUSNOTA, PENDENTE)" do
      result = sync([ PENDENTE, AGUARDANDO, FATURADO ]).call

      assert_equal 3, result[:imported]
      assert Order.find_by!(external_uid: 125_072).status_pending?
      assert Order.find_by!(external_uid: 125_073).status_awaiting?
      assert Order.find_by!(external_uid: 125_074).status_billed?
    end

    test "mapeia campos e mantém raw" do
      sync([ PENDENTE ]).call
      pedido = Order.find_by!(external_uid: 125_072)

      assert_equal 193.64, pedido.total_value.to_f
      assert_equal Date.new(2026, 7, 10), pedido.negotiation_date
      assert_equal "CLIENTE X", pedido.partner_name
      assert_equal "L", pedido.note_status
      assert pedido.pending
      assert_equal "L", pedido.raw["STATUSNOTA"]
      assert_equal "CLIENTE X", pedido.partner.name # dimensão criada por upsert
    end

    test "upsert por NUNOTA: pedido que vira nota muda de status sem duplicar" do
      sync([ PENDENTE ]).call
      assert Order.find_by!(external_uid: 125_072).status_pending?

      # Mesmo NUNOTA agora faturado (PENDENTE='N').
      result = sync([ PENDENTE.merge("PENDENTE" => "N") ]).call

      assert_equal 0, result[:imported]
      assert_equal 1, result[:updated]
      assert_equal 1, Order.where(external_uid: 125_072).count
      assert Order.find_by!(external_uid: 125_072).status_billed?
    end

    test "portfolio scope traz só pendentes" do
      sync([ PENDENTE, AGUARDANDO, FATURADO ]).call
      assert_equal [ 125_072 ], Order.portfolio.pluck(:external_uid)
    end

    test "paginação keyset por NUNOTA" do
      rows = [ PENDENTE, AGUARDANDO, FATURADO ]
      client = FakeSankhyaClient.new(rows: rows, key: "NUNOTA")
      result = Sankhya::OrderSync.new(client: client, page_size: 2).call

      assert_equal 3, result[:rows]
      assert_equal 3, Order.count
    end

    private

    def sync(rows)
      Sankhya::OrderSync.new(client: FakeSankhyaClient.new(rows: rows, key: "NUNOTA"))
    end
  end
end
