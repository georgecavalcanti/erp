# Formata notas para o front. Espera scopes com includes(:partner, :salesperson,
# :company) para evitar N+1.
class InvoiceSerializer
  def self.collection(scope, as_of: Date.current)
    scope.map { |invoice| call(invoice, as_of: as_of) }
  end

  def self.call(invoice, as_of: Date.current)
    {
      id: invoice.id,
      external_uid: invoice.external_uid,
      invoice_number: invoice.invoice_number,
      order_number: invoice.order_number,
      company: invoice.company&.name,
      partner: invoice.partner&.name,
      salesperson: invoice.salesperson&.nickname,
      negotiation_date: invoice.negotiation_date,
      total_value: invoice.total_value.to_f,
      commission: invoice.commission.to_f,
      payment_terms: invoice.payment_terms_raw,
      installment_offsets: invoice.installment_offsets,
      first_due_date: invoice.first_due_date,
      due_date: invoice.due_date,
      kind: invoice.kind,
      paid: invoice.paid,
      paid_at: invoice.paid_at,
      status: invoice.payment_status(as_of)
    }
  end
end
