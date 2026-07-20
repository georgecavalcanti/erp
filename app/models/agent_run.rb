# Auditoria do agente Claude (doc 04/09) — um registro por execução, com custo,
# tokens, ferramentas chamadas e a resposta estruturada final (`output`), que é a
# base da degradação "última resposta válida" quando a IA está indisponível.
class AgentRun < ApplicationRecord
  belongs_to :user
  has_many :recommendations, dependent: :nullify

  enum :kind, { copilot: 0, daily_plan: 1, simulation: 2, batch: 3, cockpit_summary: 4 }, prefix: :kind
  enum :status, { ok: 0, error: 1, refused: 2, invalid_schema: 3 }, prefix: :status

  scope :today, -> { where(created_at: Time.current.all_day) }

  # Última resposta VÁLIDA de um tipo para o usuário — o que o front exibe com o
  # aviso "gerado às HH:MM" quando a IA está fora do ar.
  def self.last_valid(user:, kind:)
    where(user:, kind:).status_ok.where.not(output: nil).order(created_at: :desc).first
  end

  # Tokens consumidos HOJE (todos os usuários) — comparado ao teto diário global
  # (AGENT_DAILY_TOKEN_BUDGET). Cache read não conta: custa ~0,1× e é justamente
  # a alavanca de economia que não queremos desincentivar.
  def self.tokens_spent_today
    today.sum("input_tokens + output_tokens")
  end
end
