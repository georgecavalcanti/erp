class ImportsController < ApplicationController
  KIND_LABELS = {
    "invoices" => "Notas / Devoluções",
    "delinquency" => "Inadimplência",
    "pending_orders" => "Pedidos pendentes"
  }.freeze

  def index
    render inertia: "Imports", props: {
      batches: ImportBatch.recent.includes(:user).limit(50).map { |batch| serialize_batch(batch) }
    }
  end

  def create
    file = params[:file]
    if file.blank?
      redirect_to imports_path, alert: "Selecione uma planilha (.xls, .xlsx ou .csv)."
      return
    end

    ext = detect_extension(file.original_filename)
    type = ImportTypeDetector.detect(path: file.tempfile.path, extension: ext)

    batch = ImportBatch.create!(original_filename: file.original_filename, user: Current.user, status: :pending)
    importer_for(type).call(batch: batch, path: file.tempfile.path, extension: ext)
    batch.reload

    redirect_to imports_path, notice: import_notice(type, batch)
  rescue => e
    redirect_to imports_path, alert: "Falha na importação: #{e.message}"
  end

  private

  def importer_for(type)
    {
      pending_orders: PendingOrderImporter,
      delinquency_summary: DelinquencySummaryImporter,
      delinquency_detail: DelinquencyImporter
    }.fetch(type, SpreadsheetImporter)
  end

  def import_notice(type, batch)
    case type
    when :pending_orders
      "Carteira importada: #{batch.rows_imported} pedidos pendentes."
    when :delinquency_summary, :delinquency_detail
      "Inadimplência importada: #{batch.rows_imported} registros#{type == :delinquency_detail ? ' (detalhado)' : ''}."
    else
      "Importado: #{batch.rows_imported} novas, #{batch.rows_updated} atualizadas, #{batch.rows_skipped} ignoradas."
    end
  end

  def detect_extension(filename)
    case File.extname(filename.to_s).downcase
    when ".xlsx" then :xlsx
    when ".csv"  then :csv
    else :xls
    end
  end

  def serialize_batch(batch)
    {
      id: batch.id,
      filename: batch.original_filename,
      kind: batch.kind,
      kind_label: KIND_LABELS[batch.kind] || batch.kind,
      status: batch.status,
      rows_total: batch.rows_total,
      rows_imported: batch.rows_imported,
      rows_updated: batch.rows_updated,
      rows_skipped: batch.rows_skipped,
      period_start: batch.period_start,
      period_end: batch.period_end,
      reference_date: batch.reference_date,
      error_message: batch.error_message,
      user: batch.user&.email_address,
      created_at: batch.created_at
    }
  end
end
