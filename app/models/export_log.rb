# Registro de uma exportação de dados (doc 09) — quem exportou o quê, quantas
# linhas, com que recorte e quando. Gravado por Exportable#send_registered_csv.
class ExportLog < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true
  validates :format, presence: true
  validates :row_count, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
end
