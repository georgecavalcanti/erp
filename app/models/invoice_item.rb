# Item de nota (TGFITE), espelhado por Sankhya::InvoiceItemSync.
# Valores positivos como o ERP entrega; o sinal de devolução é aplicado no
# nível da nota (Invoice#signed_value / #signed_margin), como já ocorre com
# total_value. Margem = net_value - total_cost (custo congelado na venda).
class InvoiceItem < ApplicationRecord
  belongs_to :invoice
  belongs_to :product, optional: true

  validates :external_sequence, presence: true,
                                uniqueness: { scope: :invoice_id }
  validates :quantity, :gross_value, :discount_value, :net_value, numericality: true
end
