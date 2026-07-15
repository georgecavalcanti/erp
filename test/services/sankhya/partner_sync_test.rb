require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class PartnerSyncTest < ActiveSupport::TestCase
    ROW = {
      "CODPARC" => 4242,
      "NOMEPARC" => "MERCADO EXEMPLO",
      "RAZAOSOCIAL" => "MERCADO EXEMPLO LTDA",
      "CGC_CPF" => "12345678000199",
      "ATIVO" => "S",
      "BLOQUEAR" => "N",
      "MOTBLOQ" => nil,
      "CODVEND" => 41,
      "CODTAB" => 9,
      "AD_CURVA" => "A",
      "DTULTNEGOC" => "2026-07-01",
      "NOMECID" => "PALMAS",
      "UF" => "TO",
      "DESCRTIPPARC" => "Supermercado"
    }.freeze

    test "enriquece parceiro existente sem perder o nome" do
      existente = Partner.upsert_from(external_code: 4242, name: "MERCADO EXEMPLO")

      result = PartnerSync.new(client: fake([ ROW ])).call

      assert_equal 0, result[:imported]
      assert_equal 1, result[:updated]

      existente.reload
      assert_equal "MERCADO EXEMPLO", existente.name
      assert_equal "12345678000199", existente.cnpj
      assert_equal "PALMAS", existente.city
      assert_equal "TO", existente.state
      assert_equal "Supermercado", existente.segment
      assert_equal Date.new(2026, 7, 1), existente.last_negotiation_on
      assert existente.active
      assert_not existente.blocked
      assert_equal 41, existente.raw["CODVEND"] # seed de carteiras (Sprint 3)
    end

    test "cria cliente que nunca comprou (necessário para carteiras)" do
      result = PartnerSync.new(client: fake([ ROW ])).call

      assert_equal 1, result[:imported]
      assert Partner.exists?(external_code: 4242)
    end

    test "não regride nome para vazio quando ERP manda NOMEPARC nulo" do
      Partner.upsert_from(external_code: 4242, name: "NOME BOM")

      PartnerSync.new(client: fake([ ROW.merge("NOMEPARC" => nil) ])).call

      assert_equal "NOME BOM", Partner.find_by!(external_code: 4242).name
    end

    test "mapeia bloqueio e inatividade" do
      row = ROW.merge("ATIVO" => "N", "BLOQUEAR" => "S", "MOTBLOQ" => "INADIMPLENTE")
      PartnerSync.new(client: fake([ row ])).call

      parceiro = Partner.find_by!(external_code: 4242)
      assert_not parceiro.active
      assert parceiro.blocked
      assert_equal "INADIMPLENTE", parceiro.block_reason
    end

    private

    def fake(rows)
      FakeSankhyaClient.new(rows: rows, key: "CODPARC")
    end
  end
end
