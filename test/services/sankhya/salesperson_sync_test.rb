require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class SalespersonSyncTest < ActiveSupport::TestCase
    ROW = {
      "CODVEND" => 41,
      "APELIDO" => "CARLA",
      "ATIVO" => "S",
      "EMAIL" => "Carla@Jatto.com.br",
      "TIPVEND" => "V",
      "CODGER" => 0,
      "CODEMP" => 1,
      "CODPARC" => 900,
      "PARTICMETA" => nil
    }.freeze

    test "cria e enriquece vendedor (email normalizado, tipo, raw)" do
      result = SalespersonSync.new(client: FakeSankhyaClient.new(rows: [ ROW ])).call

      assert_equal 1, result[:imported]
      vendedor = Salesperson.find_by!(external_code: 41)
      assert_equal "CARLA", vendedor.nickname
      assert_equal "carla@jatto.com.br", vendedor.email
      assert_equal "V", vendedor.seller_kind
      assert vendedor.active
      assert_equal 0, vendedor.raw["CODGER"]
    end

    test "é idempotente e marca inativos" do
      SalespersonSync.new(client: FakeSankhyaClient.new(rows: [ ROW ])).call
      result = SalespersonSync.new(client: FakeSankhyaClient.new(rows: [ ROW.merge("ATIVO" => "N") ])).call

      assert_equal 1, result[:updated]
      assert_equal 1, Salesperson.where(external_code: 41).count
      assert_not Salesperson.find_by!(external_code: 41).active
    end

    test "não regride apelido para vazio" do
      Salesperson.upsert_from(external_code: 41, nickname: "CARLA")

      SalespersonSync.new(client: FakeSankhyaClient.new(rows: [ ROW.merge("APELIDO" => nil) ])).call

      assert_equal "CARLA", Salesperson.find_by!(external_code: 41).nickname
    end
  end
end
