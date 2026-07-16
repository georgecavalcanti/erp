require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class StockSyncTest < ActiveSupport::TestCase
    setup do
      @p1 = Product.create!(external_code: 161, description: "PAPEL")
      @p2 = Product.create!(external_code: 1151, description: "SACO")
    end

    def fake(rows)
      FakeSankhyaClient.new(rows: rows, key: "CODPROD")
    end

    test "snapshot grava disponível = físico − reservado − bloqueado" do
      rows = [
        { "CODPROD" => 161, "ESTOQUE" => 100, "RESERVADO" => 20, "WMSBLOQUEADO" => 5 },
        { "CODPROD" => 1151, "ESTOQUE" => 50, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 },
        { "CODPROD" => 9999, "ESTOQUE" => 10, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 } # sem cadastro local
      ]
      r = StockSync.new(client: fake(rows)).call

      assert_equal 3, r[:rows]
      assert_equal 2, r[:stored]
      assert_equal 1, r[:missing_product]
      sl = @p1.reload.stock_level
      assert_in_delta 100, sl.on_hand, 0.001
      assert_in_delta 75, sl.sellable, 0.001 # 100 − 20 − 5
    end

    test "é snapshot: re-sync substitui o conjunto inteiro" do
      StockSync.new(client: fake([ { "CODPROD" => 161, "ESTOQUE" => 100, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 } ])).call
      StockSync.new(client: fake([ { "CODPROD" => 1151, "ESTOQUE" => 50, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 } ])).call

      assert_nil @p1.reload.stock_level     # saiu do snapshot
      assert_not_nil @p2.reload.stock_level # entrou
      assert_equal 1, StockLevel.count
    end

    test "janela vazia NÃO zera o snapshot (guard)" do
      StockSync.new(client: fake([ { "CODPROD" => 161, "ESTOQUE" => 100, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 } ])).call
      r = StockSync.new(client: fake([])).call

      assert_equal :empty_window, r[:skipped]
      assert_equal 1, StockLevel.count # preservado
    end

    test "dry_run não grava e devolve amostra" do
      r = StockSync.new(client: fake([ { "CODPROD" => 161, "ESTOQUE" => 100, "RESERVADO" => 0, "WMSBLOQUEADO" => 0 } ])).call(dry_run: true)

      assert_equal 0, StockLevel.count
      assert_equal 1, r[:sample].size
    end
  end
end
