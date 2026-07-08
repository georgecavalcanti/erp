# Importa o "Inadimplencia modelo" (resumo GERAL por vendedor: TOTAL em aberto +
# PROTESTADOS por ano + SALDO DEVEDOR). Produz um Delinquency por vendedor.
# Snapshot: substitui a inadimplência anterior.
class DelinquencySummaryImporter
  include CellCoercion
  include SalespersonMatching

  MAX_HEADER_SCAN = 15

  class ImportError < StandardError; end

  def self.call(batch:, path:, extension:)
    new(batch: batch, path: path, extension: extension).call
  end

  def initialize(batch:, path:, extension:)
    @batch = batch
    @path = path
    @extension = extension
    load_salespeople
  end

  def call
    @batch.update!(status: :processing, kind: :delinquency)
    sheet = Roo::Spreadsheet.open(@path, extension: @extension).sheet(0)
    cols, header_index = detect_header(sheet)

    rows = []
    ((header_index + 1)..sheet.last_row).each do |i|
      row = safe_row(sheet, i)
      next if row.nil?

      label = row[cols[:label]].to_s.strip
      n = normalize(label)
      next if label.blank? || n == "geral" || n.start_with?("total")

      rows << {
        import_batch: @batch,
        salesperson: match_salesperson(label),
        salesperson_label: label,
        open_total: dec(row, cols[:open]),
        protested_2024: dec(row, cols[:p2024]),
        protested_2025: dec(row, cols[:p2025]),
        protested_2026: dec(row, cols[:p2026]),
        saldo_reported: cols[:saldo] ? to_decimal(row[cols[:saldo]]) : nil
      }
    end

    Delinquency.transaction do
      Delinquency.delete_all
      OverdueTitle.delete_all # o resumo não traz detalhe — limpa detalhe antigo p/ coerência
      rows.each { |attrs| Delinquency.create!(attrs) }
    end

    @batch.update!(
      status: :completed,
      rows_total: rows.size,
      rows_imported: rows.size,
      rows_updated: 0,
      rows_skipped: 0,
      reference_date: reference_date_from_filename
    )
    @batch
  rescue => e
    @batch.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def dec(row, idx)
    idx ? to_decimal(row[idx]) : BigDecimal("0")
  end

  def detect_header(sheet)
    last = [ sheet.last_row.to_i, MAX_HEADER_SCAN ].min
    (1..last).each do |i|
      row = safe_row(sheet, i)
      next if row.nil?

      map = {}
      row.each_with_index do |cell, idx|
        n = normalize(cell)
        map[:label] ||= idx if n == "vendedor"
        map[:open]  ||= idx if n == "total"
        map[:saldo] ||= idx if n.include?("saldo")
        if n.include?("protest")
          map[:p2024] ||= idx if n.include?("2024")
          map[:p2025] ||= idx if n.include?("2025")
          map[:p2026] ||= idx if n.include?("2026")
        end
      end
      return [ map, i ] if map[:label] && map[:open]
    end

    raise ImportError, "Cabeçalho do resumo de inadimplência não reconhecido (esperava 'VENDEDOR' e 'TOTAL')."
  end

  def safe_row(sheet, row_number)
    sheet.row(row_number)
  rescue
    nil
  end

  def reference_date_from_filename
    m = @batch.original_filename.to_s.match(/(\d{2})[ ._-](\d{2})[ ._-](\d{2,4})/)
    return nil unless m

    day, month, year = m[1].to_i, m[2].to_i, m[3].to_i
    year += 2000 if year < 100
    Date.new(year, month, day)
  rescue ArgumentError
    nil
  end
end
