# Inadimplência resumida por vendedor (do "Inadimplencia modelo": TOTAL em aberto
# + protestado por ano + saldo). Snapshot: cada import substitui o anterior.
class Delinquency < ApplicationRecord
  belongs_to :import_batch, optional: true
  belongs_to :salesperson, optional: true

  validates :salesperson_label, presence: true

  def total_protested
    protested_2024 + protested_2025 + protested_2026
  end

  # Saldo recalculado (a coluna SALDO DEVEDOR da planilha tem erros manuais).
  def saldo_devedor
    open_total + total_protested
  end
end
