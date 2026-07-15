require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  # A mecânica de itens (keyset composto, margem, órfão, rollup) é coberta em
  # profundidade por InvoiceItemSyncTest — ambos herdam de Sankhya::ItemSync.
  # Aqui só garantimos que a subclasse de PEDIDO grava em order_items e
  # consolida a margem no Order certo.
  class OrderItemSyncTest < ActiveSupport::TestCase
    ITEM = {
      "NUNOTA" => 125_072, "SEQUENCIA" => 1, "CODPROD" => 161, "QTDNEG" => 10,
      "VLRUNIT" => 2.21, "VLRTOT" => 22.1, "VLRDESC" => 7.3, "CUSTO" => 1.145
    }.freeze

    setup do
      @order = Order.create!(external_uid: 125_072, total_value: 14.8, status: :pending)
      Product.create!(external_code: 161, description: "PAPEL TOALHA")
    end

    test "grava item no pedido e consolida margem" do
      client = FakeSankhyaClient.new(rows: [ ITEM ], composite: %w[NUNOTA SEQUENCIA])
      result = Sankhya::OrderItemSync.new(client: client).call

      assert_equal 1, result[:upserted]
      assert_equal 1, result[:parents_touched]
      item = @order.order_items.sole
      assert_in_delta 14.8, item.net_value, 0.001
      assert_in_delta 3.35, item.margin_value, 0.001

      @order.reload
      assert_in_delta 11.45, @order.total_cost, 0.001
      assert_in_delta 3.35, @order.margin_value, 0.001
      assert_not_nil @order.items_synced_at
    end

    test "item sem pedido local é pulado" do
      orfao = ITEM.merge("NUNOTA" => 999_999)
      client = FakeSankhyaClient.new(rows: [ orfao ], composite: %w[NUNOTA SEQUENCIA])
      result = Sankhya::OrderItemSync.new(client: client).call

      assert_equal 0, result[:upserted]
      assert_equal 1, result[:skipped_no_parent]
      assert_equal 0, OrderItem.count
    end
  end
end
