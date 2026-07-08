# Importa o relatório manual de inadimplência (.xlsx com uma aba por vendedor +
# aba GERAL de resumo). Cada aba tem seções: "em aberto" (atual) e "PROTESTADOS"
# por ano, cada uma com cabeçalho "Nro Nota | Parceiro | Dt. Vencimento | Vlr" e
# uma linha TOTAL.
#
# É um SNAPSHOT: importar substitui a inadimplência anterior (é assim que o
# relatório é mantido — sobe-se uma versão mais recente "até dd/mm/aa").
class DelinquencyImporter
  include CellCoercion
  include SalespersonMatching

  SKIP_SHEETS = %w[geral].freeze # abas de resumo (ignoradas; totais recalculados dos detalhes)
  HEADER_MARKER = "nro nota"

  class ImportError < StandardError; end

  def self.call(batch:, path:, extension:)
    new(batch: batch, path: path, extension: extension).call
  end

  def initialize(batch:, path:, extension:)
    @batch = batch
    @path = path
    @extension = extension
    load_salespeople
    @partners_index = Partner.all.index_by { |p| normalize(p.name) }
  end

  def call
    @batch.update!(status: :processing, kind: :delinquency)
    book = open_spreadsheet

    titles = []
    book.sheets.each do |sheet_name|
      next if SKIP_SHEETS.include?(normalize(sheet_name))

      titles.concat(parse_sheet(book, sheet_name))
    end

    OverdueTitle.transaction do
      OverdueTitle.delete_all # snapshot: substitui a inadimplência anterior
      titles.each { |attrs| OverdueTitle.create!(attrs) }
    end
    derive_delinquency_summary

    @batch.update!(
      status: :completed,
      rows_total: titles.size,
      rows_imported: titles.size,
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

  # Agrega os títulos detalhados no resumo por vendedor (mesmo modelo que o
  # "Inadimplencia modelo" produz), para as duas fontes alimentarem as telas.
  def derive_delinquency_summary
    Delinquency.transaction do
      Delinquency.delete_all
      OverdueTitle.all.group_by(&:salesperson_label).each do |label, titles|
        salesperson = titles.find(&:salesperson_id)&.salesperson
        by_year = ->(year) { titles.select { |t| t.category_protested? && t.protest_year == year }.sum(&:amount) }
        Delinquency.create!(
          import_batch: @batch,
          salesperson: salesperson,
          salesperson_label: label,
          open_total: titles.select(&:category_open?).sum(&:amount),
          protested_2024: by_year.call(2024),
          protested_2025: by_year.call(2025),
          protested_2026: by_year.call(2026)
        )
      end
    end
  end

  def parse_sheet(book, sheet_name)
    book.default_sheet = sheet_name
    label = sheet_name.to_s.strip
    salesperson = match_salesperson(label)
    section = { category: :open, protest_year: nil }
    result = []

    (1..book.last_row.to_i).each do |i|
      row = book.row(i)
      c0 = normalize(row[0])
      c1 = normalize(row[1])
      year = detect_year(row[4])
      nota = to_integer(row[0])

      # Cabeçalho de seção "Nro Nota | ... | <ano?>" -> aberto vs protestado.
      if c0 == HEADER_MARKER
        section = { category: year ? :protested : :open, protest_year: year }
        next
      end
      # Header malformado: só o ano do protesto na col 4, sem "Nro Nota" (o relatório
      # é manual e às vezes omite o cabeçalho completo).
      if year && nota.nil?
        section = { category: :protested, protest_year: year }
        next
      end
      next if c0.start_with?("total") || c1.start_with?("total") # linha de total
      next if c0 == normalize(label) # linha de título (nome do vendedor)

      due = to_date(row[2])
      amount = to_decimal(row[3])
      partner_name = row[1].to_s.strip.presence
      next if amount.zero? && due.nil? # linha vazia/ruído

      # "PROTESTO" na própria linha é sinal forte (sobrepõe a seção, caso um
      # marcador tenha sido omitido).
      protested = normalize(row[4]) == "protesto" || section[:category] == :protested

      result << {
        import_batch: @batch,
        salesperson: salesperson,
        salesperson_label: label,
        partner: partner_name && @partners_index[normalize(partner_name)],
        partner_name: partner_name,
        invoice_number: nota,
        due_date: due,
        amount: amount,
        category: protested ? :protested : :open,
        protest_year: protested ? section[:protest_year] : nil,
        observation: protested ? nil : observation_of(row[4])
      }
    end

    result
  end

  def open_spreadsheet
    Roo::Spreadsheet.open(@path, extension: @extension)
  rescue => e
    raise ImportError, "Não foi possível abrir a planilha de inadimplência: #{e.message}"
  end

  def detect_year(value)
    year = to_integer(value)
    year if year&.between?(2020, 2035)
  end

  def observation_of(value)
    text = value.to_s.strip
    return nil if text.empty? || normalize(text) == "protesto"

    text
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
