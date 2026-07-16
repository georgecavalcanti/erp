# Registro de relacionamento com o cliente (doc 04). Base do histórico no Cliente
# 360 e, adiante, do motor de risco (sem contato há N dias) e da receita influenciada.
class Activity < ApplicationRecord
  belongs_to :user
  belongs_to :salesperson, optional: true
  belongs_to :partner

  KINDS = { contact: 0, visit: 1, task: 2, note: 3, result: 4 }.freeze
  KIND_LABELS = {
    "contact" => "Contato", "visit" => "Visita", "task" => "Tarefa",
    "note" => "Observação", "result" => "Resultado"
  }.freeze
  enum :kind, KINDS, prefix: :kind

  def kind_label
    KIND_LABELS[kind]
  end

  validates :occurred_at, presence: true

  before_validation :default_occurred_at

  scope :recent_first, -> { order(occurred_at: :desc) }

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end
end
