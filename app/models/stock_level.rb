# Nível de estoque de um produto (TGFEST, empresa 1, local padrão). Snapshot
# atômico por Sankhya::StockSync. Base do "disponível" no Cliente 360 e das
# restrições de estoque na priorização (Sprint 7).
class StockLevel < ApplicationRecord
  belongs_to :product
  belongs_to :company, optional: true

  # Disponível para venda = físico − reservado − bloqueado (nunca negativo p/ exibir).
  def sellable
    [ on_hand - reserved - blocked, 0 ].max
  end
end
