module Sankhya
  # Itens das NOTAS (venda 1101 + devolução 1201/1202) -> InvoiceItem, com
  # consolidação de margem na nota. Mecânica na base Sankhya::ItemSync.
  #
  #   Sankhya::InvoiceItemSync.new(since: Date.new(2024, 12, 1)).call  # backfill
  #   Sankhya::InvoiceItemSync.new(changed_within_hours: 24).call      # incremental
  class InvoiceItemSync < ItemSync
    TOPS = [ 1101, 1201, 1202 ].freeze

    private

    def tops = TOPS
    def item_class = InvoiceItem
    def parent_class = Invoice
    def parent_fk = :invoice_id
    def parent_table = "invoices"
    def item_table = "invoice_items"
  end
end
