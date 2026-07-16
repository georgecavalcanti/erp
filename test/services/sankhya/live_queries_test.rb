require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class LiveQueriesTest < ActiveSupport::TestCase
    setup { @product = Product.create!(external_code: 161, description: "PAPEL") }

    test "estoque ao vivo quando o gateway responde" do
      client = FakeSankhyaClient.new(rows: [ { "ESTOQUE" => 100, "RESERVADO" => 30, "WMSBLOQUEADO" => 0 } ])
      r = LiveQueries.new(client: client).stock(@product)

      assert_equal "live", r[:source]
      assert_in_delta 70, r[:sellable], 0.001
    end

    test "fallback para o snapshot quando o gateway não traz linha" do
      @product.create_stock_level!(on_hand: 40, reserved: 10, blocked: 0, synced_at: Time.current)
      r = LiveQueries.new(client: FakeSankhyaClient.new(rows: [])).stock(@product)

      assert_equal "snapshot", r[:source]
      assert_in_delta 30, r[:sellable], 0.001
    end

    test "erro do gateway cai no snapshot (não quebra)" do
      @product.create_stock_level!(on_hand: 40, reserved: 0, blocked: 0, synced_at: Time.current)
      raising = Object.new
      def raising.execute_query(*) = raise(Sankhya::Error, "timeout")

      r = LiveQueries.new(client: raising).stock(@product)
      assert_equal "snapshot", r[:source]
    end

    test "sem snapshot e sem live: unavailable" do
      r = LiveQueries.new(client: FakeSankhyaClient.new(rows: [])).stock(@product)

      assert_equal "unavailable", r[:source]
      assert_nil r[:sellable]
    end
  end
end
