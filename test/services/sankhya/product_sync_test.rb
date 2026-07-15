require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class ProductSyncTest < ActiveSupport::TestCase
    ROW_ATIVO = {
      "CODPROD" => 1_815_627_910,
      "DESCRPROD" => "REFIL MOP PO 80CM  ",
      "CODGRUPOPROD" => 1_010_700_000,
      "DESCRGRUPOPROD" => "ACESSÓRIOS",
      "CODVOL" => "UN",
      "MARCA" => nil,
      "REFERENCIA" => "R-80",
      "NCM" => "96031000",
      "USOPROD" => "R",
      "ATIVO" => "S",
      "CODPARCFORN" => 4518,
      "DTALTER" => "2026-02-06 08:30:20"
    }.freeze

    ROW_INATIVO = ROW_ATIVO.merge(
      "CODPROD" => 161, "DESCRPROD" => "PAPEL TOALHA", "ATIVO" => "N",
      "CODGRUPOPROD" => 1_010_100_000, "DESCRGRUPOPROD" => "PAPEIS"
    ).freeze

    test "cria produtos mapeando campos do ERP" do
      sync = ProductSync.new(client: fake([ ROW_ATIVO, ROW_INATIVO ]))
      result = sync.call

      assert_equal 2, result[:imported]
      assert_equal 0, result[:updated]

      produto = Product.find_by!(external_code: 1_815_627_910)
      assert_equal "REFIL MOP PO 80CM", produto.description # strip
      assert_equal 1_010_700_000, produto.category_external_code
      assert_equal "ACESSÓRIOS", produto.category_name
      assert_equal "UN", produto.unit
      assert_equal "96031000", produto.ncm
      assert produto.active
      assert_equal "S", produto.raw["ATIVO"] # linha original preservada

      assert_not Product.find_by!(external_code: 161).active
    end

    test "é idempotente: segunda execução não duplica nem infla 'updated'" do
      ProductSync.new(client: fake([ ROW_ATIVO ])).call
      result = ProductSync.new(client: fake([ ROW_ATIVO ])).call

      assert_equal 0, result[:imported]
      assert_equal 0, result[:updated]   # linha idêntica NÃO conta como atualizada (#7)
      assert_equal 1, result[:unchanged]
      assert_equal 1, Product.where(external_code: 1_815_627_910).count
    end

    test "mudança real conta como updated (não unchanged)" do
      ProductSync.new(client: fake([ ROW_ATIVO ])).call
      result = ProductSync.new(client: fake([ ROW_ATIVO.merge("DESCRPROD" => "REFIL MOP NOVO") ])).call

      assert_equal 0, result[:imported]
      assert_equal 1, result[:updated]
      assert_equal 0, result[:unchanged]
      assert_equal "REFIL MOP NOVO", Product.find_by!(external_code: 1_815_627_910).description
    end

    test "pagina por keyset até esgotar as linhas" do
      rows = [ ROW_ATIVO, ROW_INATIVO, ROW_ATIVO.merge("CODPROD" => 999) ]
      client = fake(rows)

      result = ProductSync.new(client: client, page_size: 2).call

      assert_equal 3, result[:rows]
      assert_equal 3, Product.count
      assert_equal 2, client.queries.size # página cheia + página parcial (encerra)
    end

    test "linha inválida é pulada sem abortar o lote" do
      sem_descricao = ROW_ATIVO.merge("CODPROD" => 7, "DESCRPROD" => "  ")
      result = ProductSync.new(client: fake([ sem_descricao, ROW_INATIVO ])).call

      assert_equal 1, result[:skipped]
      assert_equal 1, result[:imported]
      assert_nil Product.find_by(external_code: 7)
    end

    test "dry_run não grava e devolve amostra" do
      result = ProductSync.new(client: fake([ ROW_ATIVO ])).call(dry_run: true)

      assert_equal 0, Product.count
      assert_equal 1, result[:sample].size
      assert_equal 1_815_627_910, result[:sample].first[:external_code]
    end

    private

    def fake(rows)
      FakeSankhyaClient.new(rows: rows, key: "CODPROD")
    end
  end
end
