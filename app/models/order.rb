# Histórico persistente de pedidos de venda (TOP 1001), espelhado por
# Sankhya::OrderSync (upsert por NUNOTA). Base analítica para projeção e
# cross-sell. A carteira "a faturar" é o subconjunto `pending`.
#
# Não confundir com PendingOrder (snapshot que ainda alimenta a tela Carteira);
# ver docs/forca-de-vendas-360/04-modelo-de-dados.md.
class Order < ApplicationRecord
  belongs_to :company,     optional: true
  belongs_to :partner,     optional: true
  belongs_to :salesperson, optional: true
  has_many :order_items, dependent: :delete_all

  # Ciclo de vida do pedido (Fase 0): pending = a faturar; awaiting = aguardando
  # liberação; billed = já faturado (virou nota).
  enum :status, { pending: 0, awaiting: 1, billed: 2 }, prefix: :status

  validates :external_uid, presence: true, uniqueness: true
  validates :total_value, numericality: true

  # Carteira a faturar = pedidos pendentes (qualquer mês).
  scope :portfolio, -> { status_pending }
end
