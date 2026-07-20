# Auditoria do agente Claude (doc 04/09) — um registro por execução, com custo,
# tokens, ferramentas chamadas e a resposta estruturada final (`output`), que é a
# base da degradação "última resposta válida" quando a IA está indisponível.
class AgentRun < ApplicationRecord
  belongs_to :user
  belongs_to :salesperson, optional: true # vendedor de CONTEXTO da execução
  has_many :recommendations, dependent: :nullify

  enum :kind, { copilot: 0, daily_plan: 1, simulation: 2, batch: 3, cockpit_summary: 4 }, prefix: :kind
  enum :status, { ok: 0, error: 1, refused: 2, invalid_schema: 3 }, prefix: :status

  scope :today, -> { where(created_at: Time.current.all_day) }
  scope :this_month, -> { where(created_at: Time.current.all_month) }

  # Última resposta VÁLIDA de um tipo para (usuário, vendedor de contexto) — o
  # que o front exibe com "gerado às HH:MM" quando a IA cai. O recorte por
  # vendedor evita que um gestor alternando carteiras veja o resumo de A em B.
  def self.last_valid(user:, kind:, salesperson: nil)
    scope = where(user:, kind:).status_ok.where.not(output: nil)
    scope = scope.where(salesperson: salesperson) if salesperson
    scope.order(created_at: :desc).first
  end

  # Custo (US$) gasto no MÊS corrente — base do teto global (orçamento de fato).
  # Conta TODOS os tipos (copiloto + resumo + abordagens). cost_estimate nil
  # (modelo sem preço na tabela) conta como 0 — o backstop de tokens cobre.
  def self.cost_spent_this_month
    this_month.sum(:cost_estimate).to_f
  end

  # Custo (US$) gasto HOJE no contexto de UM vendedor — teto por vendedor/dia.
  def self.cost_spent_today_for(salesperson_id)
    today.where(salesperson_id: salesperson_id).sum(:cost_estimate).to_f
  end

  # Tokens consumidos HOJE (todos os usuários) — backstop absoluto
  # (AGENT_DAILY_TOKEN_BUDGET). Escrita de cache conta (é cobrada a 1,25×);
  # cache READ não conta: custa ~0,1× e é a alavanca de economia que não
  # queremos desincentivar.
  def self.tokens_spent_today
    today.sum("input_tokens + output_tokens + cache_write_tokens")
  end
end
