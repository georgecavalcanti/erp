require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class CostSyncTest < ActiveSupport::TestCase
    setup do
      @p1 = Product.create!(external_code: 161, description: "PAPEL TOALHA")
      @p2 = Product.create!(external_code: 1151, description: "SACO LIXO")
    end

    test "atualiza current_cost dos produtos existentes" do
      rows = [
        { "CODPROD" => 161, "CUSGER" => 8.9925, "DTATUAL" => "2026-07-15" },
        { "CODPROD" => 1151, "CUSGER" => 122.68667, "DTATUAL" => "2026-07-14" }
      ]
      result = Sankhya::CostSync.new(client: fake(rows)).call

      assert_equal 2, result[:updated]
      assert_equal 0, result[:missing]
      assert_in_delta 8.9925, @p1.reload.current_cost, 0.0001
      assert_in_delta 122.68667, @p2.reload.current_cost, 0.0001
    end

    test "custo de produto não cadastrado é contado como missing" do
      rows = [ { "CODPROD" => 999, "CUSGER" => 5.0, "DTATUAL" => "2026-07-15" } ]
      result = Sankhya::CostSync.new(client: fake(rows)).call

      assert_equal 0, result[:updated]
      assert_equal 1, result[:missing]
    end

    test "dry_run não grava" do
      rows = [ { "CODPROD" => 161, "CUSGER" => 8.99, "DTATUAL" => "2026-07-15" } ]
      Sankhya::CostSync.new(client: fake(rows)).call(dry_run: true)

      assert_nil @p1.reload.current_cost
    end

    private

    def fake(rows)
      FakeSankhyaClient.new(rows: rows, key: "CODPROD")
    end
  end
end
