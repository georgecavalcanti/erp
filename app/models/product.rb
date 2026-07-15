# Espelho do catálogo do Sankhya (TGFPRO + grupo TGFGRU), dimensão do FV360.
# Escrita exclusiva do Sankhya::ProductSync (upsert por CODPROD); `current_cost`
# é atualizado pelo CostSync (Sprint 2). Itens de nota/pedido apontam para cá.
class Product < ApplicationRecord
  validates :external_code, presence: true, uniqueness: true
  validates :description, presence: true

  scope :active, -> { where(active: true) }
end
