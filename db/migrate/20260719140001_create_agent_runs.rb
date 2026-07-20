class CreateAgentRuns < ActiveRecord::Migration[8.1]
  # Auditoria do agente Claude (doc 04/09): TODA execução grava um registro com
  # modelo, ferramentas chamadas (nome/parâmetros/duração), tokens, custo,
  # latência e status. É a fonte da tela de auditoria (Sprint 9), do teto diário
  # de tokens e da degradação "última resposta válida" (coluna `output`).
  #
  #   kind:   0 copilot · 1 daily_plan · 2 simulation · 3 batch · 4 cockpit_summary
  #   status: 0 ok · 1 error · 2 refused · 3 invalid_schema
  def change
    create_table :agent_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.string :prompt_summary                              # pergunta resumida (sem PII além do necessário)
      t.string :model                                       # id do modelo usado (haiku/sonnet)
      t.jsonb :tools_called, null: false, default: []       # [{ name:, params:, duration_ms: }]
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_tokens, null: false, default: 0 # leitura de prompt cache (~0,1× do input)
      t.decimal :cost_estimate, precision: 10, scale: 6     # US$ estimado (preços em Agent::Config)
      t.integer :latency_ms
      t.integer :status, null: false, default: 0
      t.string :error_detail
      t.string :response_digest                             # SHA da resposta (dedupe de pergunta idêntica)
      t.jsonb :output                                       # resposta estruturada final — degradação sem IA
      t.timestamps
    end

    # Teto diário e auditoria consultam "runs do usuário no dia" — índice composto.
    add_index :agent_runs, %i[user_id created_at]
    add_index :agent_runs, %i[kind created_at]

    # A FK prometida na Sprint 7 (recommendations.agent_run_id sem FK até existir a tabela).
    add_foreign_key :recommendations, :agent_runs
    add_index :recommendations, :agent_run_id
  end
end
