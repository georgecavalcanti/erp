# Item de pedido (TGFITE dos pedidos TOP 1001), espelhado por
# Sankhya::OrderItemSync. Mesma estrutura de InvoiceItem — alimenta cross-sell
# (produtos na carteira) e margem projetada dos pendentes.
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, optional: true

  validates :external_sequence, presence: true,
                                uniqueness: { scope: :order_id }
  validates :quantity, :gross_value, :discount_value, :net_value, numericality: true
end
