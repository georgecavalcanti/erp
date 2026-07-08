class ImportBatch < ApplicationRecord
  belongs_to :user, optional: true
  has_many :invoices, dependent: :nullify
  has_many :overdue_titles, dependent: :destroy
  has_many :pending_orders, dependent: :destroy
  has_many :delinquencies, dependent: :destroy

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  # invoices = Cabeçalho da Nota (vendas + devoluções) · delinquency = inadimplência
  # pending_orders = carteira de pedidos a faturar
  enum :kind, { invoices: 0, delinquency: 1, pending_orders: 2 }, prefix: :kind

  validates :original_filename, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def rows_processed
    rows_imported + rows_updated
  end
end
