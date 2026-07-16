# Previsão de recompra de um parceiro (doc 04/05.2), gravada por
# Engines::Repurchase. Estágio estatístico: data esperada = última compra +
# mediana do intervalo entre compras. Versionada — cada leva do lote noturno cria
# novas previsões `open` (uma por alvo); a conciliação transiciona para
# `confirmed`/`missed`. NÃO confundir com o motor Engines::Repurchase (que calcula).
class RepurchasePrediction < ApplicationRecord
  belongs_to :partner
  belongs_to :product, optional: true
  belongs_to :confirmed_invoice, class_name: "Invoice", optional: true

  # Nível da previsão (doc 05.2): o cliente em geral, uma categoria, ou um produto.
  enum :level, { customer: 0, category: 1, product: 2 }, prefix: :level
  # Ciclo de vida (aprendizado): open → confirmed (comprou) / missed (venceu sem
  # compra nem pedido) / canceled (superada por recálculo).
  enum :status, { open: 0, confirmed: 1, missed: 2, canceled: 3 }, prefix: :status

  validates :target_key, presence: true
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true

  scope :open_predictions, -> { status_open }
  # Recompra ATRASADA: previsão aberta cuja data esperada já venceu (doc 05.2).
  scope :overdue, ->(as_of = Date.current) { status_open.where(expected_date: ...as_of) }
  scope :for_partner, ->(partner_id) { where(partner_id: partner_id) }
end
