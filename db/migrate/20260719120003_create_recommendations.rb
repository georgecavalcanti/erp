class CreateRecommendations < ActiveRecord::Migration[8.1]
  # Recomendação — formato padrão (doc 04/06). No MVP (Sprint 7) é gerada
  # DETERMINISTICAMENTE a partir de uma `priority`; na Sprint 8 o agente Claude
  # passa a preenchê-la (por isso `agent_run_id`, ainda sem tabela → coluna sem FK).
  # É o registro com que o vendedor interage no Plano do Dia (status + feedback).
  #
  #   channel: 0 call · 1 whatsapp · 2 visit · 3 email · 4 internal
  #   status:  0 pending · 1 accepted · 2 postponed · 3 discarded · 4 done
  #   feedback: 0 useful · 1 not_useful (null = sem feedback)
  def change
    create_table :recommendations do |t|
      t.references :user, foreign_key: true                    # dono da ação (vendedor logado)
      t.references :salesperson, null: false, foreign_key: true
      t.references :partner, foreign_key: true
      t.references :priority, foreign_key: true                # origem determinística (MVP)
      t.date :reference_date, null: false

      t.string :diagnosis
      t.string :recommendation
      t.jsonb :evidences, null: false, default: []
      t.jsonb :potential_impact, null: false, default: {}      # { revenue:, margin:, retention: }
      t.integer :confidence                                    # 0–100
      t.string :next_action
      t.integer :channel
      t.date :deadline
      t.jsonb :restrictions, null: false, default: []
      t.jsonb :tools_used, null: false, default: []
      t.bigint :agent_run_id                                   # FK vira na Sprint 8 (agent_runs)

      t.integer :status, null: false, default: 0
      t.integer :feedback
      t.string :feedback_notes
      t.datetime :acted_at
      t.timestamps
    end

    add_index :recommendations, %i[salesperson_id reference_date status]
    add_index :recommendations, %i[partner_id reference_date]
  end
end
