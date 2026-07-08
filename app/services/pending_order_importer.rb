# Importa o relatório de "Pedido Pendente" (carteira de pedidos liberados mas
# ainda não faturados). Mesmo formato "Cabeçalho da Nota", mas sem Nro. Único e
# sem códigos de parceiro/vendedor — casa por nome/apelido.
#
# É um SNAPSHOT: importar substitui a carteira anterior (pedidos viram nota ou
# são cancelados ao longo do tempo).
class PendingOrderImporter
  include CellCoercion

  HEADER_MAP = {
    "pedido foi impresso?" => :printed,
    "nro. nota" => :external_uid,
    "dt. neg." => :negotiation_date,
    "status da nota" => :note_status,
    "dt. do movimento" => :movement_date,
    "nome parceiro (parceiro)" => :partner_name,
    "vlr. nota" => :total_value,
    "comissao" => :commission,
    "apelido (vendedor)" => :salesperson_nickname,
    "descricao (tipo de operacao)" => :operation_type_desc,
    "confirmada" => :confirmed,
    "retira/entrega" => :delivery_type,
    "pendente" => :pending
  }.freeze
  REQUIRED_HEADERS = %i[external_uid total_value].freeze
  MAX_HEADER_SCAN = 25

  class ImportError < StandardError; end

  def self.call(batch:, path:, extension:)
    new(batch: batch, path: path, extension: extension).call
  end

  def initialize(batch:, path:, extension:)
    @batch = batch
    @path = path
    @extension = extension
    @salespeople = Salesperson.all.index_by { |s| normalize(s.nickname) }
    @partners = Partner.all.index_by { |p| normalize(p.name) }
  end

  def call
    @batch.update!(status: :processing, kind: :pending_orders)
    sheet = open_sheet
    header_index, columns, labels = detect_header(sheet)

    rows = []
    dates = []
    ((header_index + 1)..sheet.last_row).each do |i|
      row = safe_row(sheet, i)
      next if row.nil?

      get = ->(key) { (idx = columns[key]) ? row[idx] : nil }
      external_uid = to_integer(get.call(:external_uid))
      next if external_uid.nil?

      neg = to_date(get.call(:negotiation_date))
      nick = get.call(:salesperson_nickname).to_s.strip.presence
      pname = get.call(:partner_name).to_s.strip.presence

      rows << {
        external_uid: external_uid,
        order_number: external_uid,
        salesperson: nick && @salespeople[normalize(nick)],
        salesperson_label: nick,
        partner: pname && @partners[normalize(pname)],
        partner_name: pname,
        negotiation_date: neg,
        movement_date: to_date(get.call(:movement_date)),
        total_value: to_decimal(get.call(:total_value)),
        commission: to_decimal(get.call(:commission)),
        operation_type_desc: get.call(:operation_type_desc).to_s.presence,
        note_status: get.call(:note_status).to_s.presence,
        delivery_type: get.call(:delivery_type).to_s.presence,
        pending: to_bool_sim(get.call(:pending)),
        printed: to_bool_sim(get.call(:printed)),
        import_batch: @batch,
        raw: build_raw(labels, row)
      }
      dates << neg if neg
    end

    PendingOrder.transaction do
      PendingOrder.delete_all # snapshot: substitui a carteira anterior
      rows.each { |attrs| PendingOrder.create!(attrs) }
    end

    @batch.update!(
      status: :completed,
      rows_total: rows.size,
      rows_imported: rows.size,
      rows_updated: 0,
      rows_skipped: 0,
      period_start: dates.min,
      period_end: dates.max
    )
    @batch
  rescue => e
    @batch.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def open_sheet
    Roo::Spreadsheet.open(@path, extension: @extension).sheet(0)
  rescue => e
    raise ImportError, "Não foi possível abrir a planilha de pedidos: #{e.message}"
  end

  def detect_header(sheet)
    best = { score: 0, index: nil, columns: {}, labels: {} }
    last = [ sheet.last_row.to_i, MAX_HEADER_SCAN ].min

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
      best = { score: columns.size, index: row_number, columns: columns, labels: labels } if columns.size > best[:score]
    end

    unless best[:index] && REQUIRED_HEADERS.all? { |k| best[:columns].key?(k) }
      raise ImportError, "Cabeçalho de pedidos não reconhecido (esperava 'Nro. Nota', 'Vlr. Nota', 'Pendente')."
    end

    [ best[:index], best[:columns], best[:labels] ]
  end

  def safe_row(sheet, row_number)
    sheet.row(row_number)
  rescue
    nil
  end

  def build_raw(labels, row)
    labels.each_with_object({}) do |(idx, label), acc|
      value = row[idx]
      acc[label] = value.is_a?(Date) ? value.iso8601 : value
    end
  end
end
