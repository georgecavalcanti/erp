require "test_helper"
require_relative "../../test_helpers/fake_sankhya_client"

module Sankhya
  class InvoiceItemSyncTest < ActiveSupport::TestCase
    # Nota 125075 da Fase 0 (produção). Desconto do item NÃO está em VLRTOT;
    # net = VLRTOT - VLRDESC; margem = net - QTDNEG*CUSTO.
    ITEM1 = {
      "NUNOTA" => 125_075, "SEQUENCIA" => 1, "CODPROD" => 161, "QTDNEG" => 10,
      "VLRUNIT" => 2.21, "VLRTOT" => 22.1, "VLRDESC" => 7.3, "CUSTO" => 1.145
    }.freeze
    ITEM2 = {
      "NUNOTA" => 125_075, "SEQUENCIA" => 2, "CODPROD" => 1151, "QTDNEG" => 10,
      "VLRUNIT" => 14.03, "VLRTOT" => 140.3, "VLRDESC" => 46, "CUSTO" => 7.27
    }.freeze

    setup do
      @invoice = Invoice.create!(external_uid: 125_075, negotiation_date: Date.new(2026, 7, 1),
                                 total_value: 109.1, kind: :sale)
      @p161 = Product.create!(external_code: 161, description: "PAPEL TOALHA")
      # CODPROD 1151 propositalmente não cadastrado -> product_id fica nil.
    end

    test "grava itens e consolida margem na nota" do
      result = sync([ ITEM1, ITEM2 ]).call

      assert_equal 2, result[:upserted]
      assert_equal 1, result[:invoices_touched]
      assert_equal 0, result[:skipped_no_invoice]
      assert_equal 2, @invoice.invoice_items.count

      item1 = @invoice.invoice_items.find_by(external_sequence: 1)
      assert_equal @p161.id, item1.product_id
      assert_in_delta 14.8, item1.net_value, 0.001         # 22.1 - 7.3
      assert_in_delta 11.45, item1.total_cost, 0.001       # 10 * 1.145
      assert_in_delta 3.35, item1.margin_value, 0.001      # 14.8 - 11.45

      assert_nil @invoice.invoice_items.find_by(external_sequence: 2).product_id # 1151 não cadastrado

      @invoice.reload
      assert_in_delta 84.15, @invoice.total_cost, 0.001    # 11.45 + 72.7
      assert_in_delta 24.95, @invoice.margin_value, 0.001  # 3.35 + 21.6
      assert_in_delta 22.869, @invoice.margin_percent, 0.01 # 24.95 / 109.1 * 100
      assert_not_nil @invoice.items_synced_at
    end

    test "item de nota fora do espelho é pulado sem quebrar" do
      orfao = ITEM1.merge("NUNOTA" => 999_999)
      result = sync([ ITEM1, orfao ]).call

      assert_equal 1, result[:upserted]
      assert_equal 1, result[:skipped_no_invoice]
      assert_equal 1, InvoiceItem.count
    end

    test "custo ausente deixa margem nula sem abortar" do
      result = sync([ ITEM1.merge("CUSTO" => nil) ]).call

      assert_equal 1, result[:upserted]
      item = @invoice.invoice_items.first
      assert_nil item.unit_cost
      assert_nil item.total_cost
      assert_nil item.margin_value
      @invoice.reload
      assert_nil @invoice.margin_value # SUM de um único item nulo = nulo
    end

    test "é idempotente: re-sync atualiza sem duplicar" do
      sync([ ITEM1, ITEM2 ]).call
      result = sync([ ITEM1.merge("VLRDESC" => 0), ITEM2 ]).call # item1 sem desconto agora

      assert_equal 2, @invoice.invoice_items.count
      item1 = @invoice.invoice_items.find_by(external_sequence: 1)
      assert_in_delta 22.1, item1.net_value, 0.001 # atualizado (sem desconto)
      assert_equal 1, result[:invoices_touched]
    end

    test "keyset composto pagina sem partir nota entre páginas" do
      # 3 itens em 2 notas; page_size 2 força a virada no meio da nota 125075.
      i3 = ITEM1.merge("NUNOTA" => 125_076, "SEQUENCIA" => 1)
      Invoice.create!(external_uid: 125_076, negotiation_date: Date.new(2026, 7, 2), total_value: 14.8, kind: :sale)

      client = FakeSankhyaClient.new(rows: [ ITEM1, ITEM2, i3 ], composite: %w[NUNOTA SEQUENCIA])
      result = Sankhya::InvoiceItemSync.new(client: client, page_size: 2).call

      assert_equal 3, result[:upserted]
      assert_equal 2, result[:invoices_touched]
      assert_equal 3, InvoiceItem.count
      assert result[:rows] >= 3 # varreu ao menos as 3 linhas
    end

    test "dry_run não grava e devolve amostra" do
      result = sync([ ITEM1, ITEM2 ]).call(dry_run: true)

      assert_equal 0, InvoiceItem.count
      assert_nil @invoice.reload.margin_value
      assert_equal 2, result[:sample].size
    end

    private

    def sync(rows)
      client = FakeSankhyaClient.new(rows: rows, composite: %w[NUNOTA SEQUENCIA])
      Sankhya::InvoiceItemSync.new(client: client, page_size: 1000)
    end
  end
end
