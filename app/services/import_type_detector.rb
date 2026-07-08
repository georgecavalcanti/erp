# Descobre o tipo da planilha pelos rótulos da primeira aba e pelo nº de abas:
#   :invoices            -> Cabeçalho da Nota (vendas + devoluções) — tem "Nro. Único"
#   :pending_orders      -> Pedido Pendente — tem coluna "Pendente"
#   :delinquency_summary -> Inadimplência modelo (resumo GERAL) — tem "SALDO DEVEDOR"
#   :delinquency_detail  -> Inadimplência detalhada (uma aba por vendedor)
class ImportTypeDetector
  include CellCoercion

  def self.detect(path:, extension:)
    new(path, extension).detect
  end

  def initialize(path, extension)
    @path = path
    @extension = extension
  end

  def detect
    book = Roo::Spreadsheet.open(@path, extension: @extension)
    sheets = book.sheets
    book.default_sheet = sheets.first
    blob = (1..[ book.last_row.to_i, 30 ].min).flat_map { |i| book.row(i) }.map { |cell| normalize(cell) }

    return :invoices if blob.include?("nro. unico")
    return :pending_orders if blob.include?("pendente")
    return :delinquency_detail if sheets.size > 3 # uma aba por vendedor
    return :delinquency_summary if blob.include?("saldo devedor") || blob.include?("vendedor")
    return :delinquency_detail if blob.include?("dt. vencimento")

    :invoices # padrão: deixa o SpreadsheetImporter validar
  rescue
    :invoices
  end
end
