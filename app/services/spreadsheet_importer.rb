# Lê a planilha de faturamento exportada do ERP (formato Sankhya "Cabeçalho da
# Nota") e materializa Empresas, Parceiros, Vendedores e Notas.
#
# Robustez:
#   * detecta a linha de cabeçalho por rótulo (ignora título/metadados no topo);
#   * mapeia colunas por nome, não por posição (tolerante a reordenação);
#   * faz upsert por "Nro. Único" -> reimportar o mesmo período é seguro;
#   * NUNCA sobrescreve `paid`/`paid_at` (controle manual do usuário é preservado).
class SpreadsheetImporter
  include CellCoercion

  # Rótulos do cabeçalho (já sem acento e minúsculos) -> chaves internas.
  HEADER_MAP = {
    "nro. nota" => :invoice_number,
    "nome parceiro (parceiro)" => :partner_name,
    "vlr. nota" => :total_value,
    "descricao (tipo de negociacao)" => :payment_terms,
    "comissao" => :commission,
    "empresa" => :company_code,
    "nome fantasia (empresa)" => :company_name,
    "pedido geral" => :order_number,
    "nro. unico" => :external_uid,
    "dt. neg." => :negotiation_date,
    "confirmada" => :confirmed,
    "parceiro" => :partner_code,
    "status nf-e" => :nfe_status,
    "status nfs-e" => :nfse_status,
    "vendedor" => :salesperson_code,
    "apelido (vendedor)" => :salesperson_nickname,
    "natureza" => :nature_code,
    "descricao (natureza)" => :nature_desc,
    "centro resultado" => :result_center_code,
    "descricao (centro de resultado)" => :result_center_desc,
    "descricao (tipo de operacao)" => :operation_type_desc
  }.freeze

  # Chaves mínimas para reconhecer a linha de cabeçalho.
  REQUIRED_HEADERS = %i[external_uid negotiation_date total_value].freeze
  MAX_HEADER_SCAN = 25

  class ImportError < StandardError; end

  def self.call(batch:, path:, extension:)
    new(batch: batch, path: path, extension: extension).call
  end

  def initialize(batch:, path:, extension:)
    @batch = batch
    @path = path
    @extension = extension
    @companies = {}
    @partners = {}
    @salespeople = {}
  end

  def call
    @batch.update!(status: :processing)
    sheet = open_sheet
    header_index, columns, labels = detect_header(sheet)

    imported = updated = skipped = 0
    dates = []

    ((header_index + 1)..sheet.last_row).each do |row_number|
      row = safe_row(sheet, row_number)
      next if row.nil?

      get = ->(key) { (idx = columns[key]) ? row[idx] : nil }

      external_uid = to_integer(get.call(:external_uid))
      negotiation_date = to_date(get.call(:negotiation_date))

      # Ignora linhas de total/rodapé/vazias (sem identidade ou sem data).
      if external_uid.nil? || negotiation_date.nil?
        skipped += 1
        next
      end

      begin
        new_record = upsert_invoice(get, external_uid, negotiation_date, row, labels)
        new_record ? imported += 1 : updated += 1
        dates << negotiation_date
      rescue => e
        Rails.logger.warn("[SpreadsheetImporter] linha #{row_number} ignorada: #{e.message}")
        skipped += 1
      end
    end

    @batch.update!(
      status: :completed,
      rows_total: imported + updated + skipped,
      rows_imported: imported,
      rows_updated: updated,
      rows_skipped: skipped,
      period_start: dates.min,
      period_end: dates.max
    )
    @batch
  rescue => e
    @batch.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def upsert_invoice(get, external_uid, negotiation_date, row, labels)
    company = fetch_company(to_integer(get.call(:company_code)), get.call(:company_name))
    partner = fetch_partner(to_integer(get.call(:partner_code)), get.call(:partner_name))
    seller  = fetch_salesperson(to_integer(get.call(:salesperson_code)), get.call(:salesperson_nickname))

    operation_type_desc = get.call(:operation_type_desc).presence&.to_s
    nature_desc = get.call(:nature_desc).presence&.to_s
    kind = InvoiceClassifier.kind_for(operation_type_desc: operation_type_desc, nature_desc: nature_desc)
    terms = PaymentTermsParser.call(get.call(:payment_terms), negotiation_date: negotiation_date)

    invoice = Invoice.find_or_initialize_by(external_uid: external_uid)
    was_new = invoice.new_record?

    invoice.assign_attributes(
      invoice_number: to_integer(get.call(:invoice_number)),
      order_number: to_integer(get.call(:order_number)),
      company: company,
      partner: partner,
      salesperson: seller,
      import_batch: @batch,
      negotiation_date: negotiation_date,
      total_value: to_decimal(get.call(:total_value)),
      commission: to_decimal(get.call(:commission)),
      payment_terms_raw: get.call(:payment_terms).presence&.to_s,
      operation_type_desc: operation_type_desc,
      nature_desc: nature_desc,
      result_center_desc: get.call(:result_center_desc).presence&.to_s,
      nfe_status: get.call(:nfe_status).presence&.to_s,
      nfse_status: get.call(:nfse_status).presence&.to_s,
      confirmed: to_bool_sim(get.call(:confirmed)),
      kind: kind,
      installment_offsets: terms.offsets,
      first_due_date: terms.first_due_date,
      due_date: terms.due_date,
      raw: build_raw(labels, row)
    )
    # paid / paid_at deliberadamente intocados: preserva o controle manual.
    invoice.save!
    was_new
  end

  # --- Caches para evitar N consultas em arquivos grandes ---
  def fetch_company(code, name)
    return nil if code.nil?
    @companies[code] ||= Company.upsert_from(external_code: code, name: name.to_s)
  end

  def fetch_partner(code, name)
    return nil if code.nil?
    @partners[code] ||= Partner.upsert_from(external_code: code, name: name.to_s)
  end

  def fetch_salesperson(code, nickname)
    return nil if code.nil?
    @salespeople[code] ||= Salesperson.upsert_from(external_code: code, nickname: nickname.to_s)
  end

  # --- Leitura da planilha ---
  def open_sheet
    Roo::Spreadsheet.open(@path, extension: @extension).sheet(0)
  rescue => e
    raise ImportError, "Não foi possível abrir a planilha (#{@extension}): #{e.message}"
  end

  def detect_header(sheet)
    best = { score: 0, index: nil, columns: {}, labels: {} }
    last = [sheet.last_row.to_i, MAX_HEADER_SCAN].min

    (1..last).each do |row_number|
      row = safe_row(sheet, row_number)
      next if row.nil?

      columns = {}
      labels = {}
      row.each_with_index do |cell, idx|
        key = HEADER_MAP[normalize(cell)]
        next unless key

        columns[key] = idx
        labels[idx] = cell.to_s
      end

      if columns.size > best[:score]
        best = { score: columns.size, index: row_number, columns: columns, labels: labels }
      end
    end

    unless best[:index] && REQUIRED_HEADERS.all? { |k| best[:columns].key?(k) }
      raise ImportError, "Cabeçalho não reconhecido (esperava colunas como 'Nro. Único', 'Dt. Neg.', 'Vlr. Nota')."
    end

    [best[:index], best[:columns], best[:labels]]
  end

  def safe_row(sheet, row_number)
    sheet.row(row_number)
  rescue
    nil
  end

  # Guarda a linha original (rótulo do ERP -> valor) para auditoria/pivotagens futuras.
  def build_raw(labels, row)
    labels.each_with_object({}) do |(idx, label), acc|
      value = row[idx]
      acc[label] = value.is_a?(Date) ? value.iso8601 : value
    end
  end
end
