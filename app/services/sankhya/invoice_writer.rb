module Sankhya
  # Faz o upsert de uma nota (venda/devolução) no modelo Invoice a partir de
  # atributos JÁ NORMALIZADOS (produzidos pelo sync da API). Idempotente por
  # NUNOTA (external_uid) — re-sincronizar a mesma nota atualiza no lugar.
  #
  # É o ÚNICO caminho de escrita de Invoice na era API-only: substitui o
  # `upsert_invoice` do antigo SpreadsheetImporter, reusando a mesma lógica de
  # dimensões (upsert_from por código), classificação (InvoiceClassifier) e
  # prazos (PaymentTermsParser). NUNCA toca `paid`/`paid_at` — controle manual.
  #
  #   writer = Sankhya::InvoiceWriter.new(batch: sync_batch)
  #   writer.upsert(external_uid: 123, negotiation_date: date, total_value: ...,
  #                 partner_code: 42, salesperson_code: 7, ...)
  class InvoiceWriter
    # Chaves aceitas em `attrs` (external_uid e negotiation_date obrigatórias):
    #   :external_uid, :invoice_number, :order_number,
    #   :company_code, :company_name,
    #   :partner_code, :partner_name,
    #   :salesperson_code, :salesperson_nickname,
    #   :negotiation_date, :total_value, :commission,
    #   :payment_terms_raw, :operation_type_desc, :nature_desc,
    #   :result_center_desc, :nfe_status, :nfse_status, :confirmed, :raw
    def initialize(batch: nil)
      @batch = batch
      # Caches para não repetir upsert de dimensão a cada nota do lote.
      @companies = {}
      @partners = {}
      @salespeople = {}
    end

    # Retorna true se criou uma nota nova, false se atualizou existente.
    def upsert(attrs)
      external_uid = attrs.fetch(:external_uid)
      negotiation_date = attrs[:negotiation_date]

      company = fetch_company(attrs[:company_code], attrs[:company_name])
      partner = fetch_partner(attrs[:partner_code], attrs[:partner_name])
      seller  = fetch_salesperson(attrs[:salesperson_code], attrs[:salesperson_nickname])

      kind = InvoiceClassifier.kind_for(
        operation_type_desc: attrs[:operation_type_desc],
        nature_desc: attrs[:nature_desc]
      )
      terms = PaymentTermsParser.call(attrs[:payment_terms_raw], negotiation_date: negotiation_date)

      invoice = Invoice.find_or_initialize_by(external_uid: external_uid)
      was_new = invoice.new_record?

      invoice.assign_attributes(
        invoice_number: attrs[:invoice_number],
        order_number: attrs[:order_number],
        company: company,
        partner: partner,
        salesperson: seller,
        import_batch: @batch,
        negotiation_date: negotiation_date,
        # total_value/commission são NOT NULL default 0 no banco: nunca grave nil.
        total_value: attrs[:total_value] || 0,
        commission: attrs[:commission] || 0,
        payment_terms_raw: attrs[:payment_terms_raw].presence&.to_s,
        operation_type_desc: attrs[:operation_type_desc].presence&.to_s,
        nature_desc: attrs[:nature_desc].presence&.to_s,
        result_center_desc: attrs[:result_center_desc].presence&.to_s,
        nfe_status: attrs[:nfe_status].presence&.to_s,
        nfse_status: attrs[:nfse_status].presence&.to_s,
        confirmed: attrs.fetch(:confirmed, true),
        kind: kind,
        installment_offsets: terms.offsets,
        first_due_date: terms.first_due_date,
        due_date: terms.due_date,
        raw: attrs[:raw] || {}
      )
      # paid / paid_at deliberadamente intocados.
      invoice.save!
      was_new
    end

    private

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
  end
end
