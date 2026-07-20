class CreatePriorities < ActiveRecord::Migration[8.1]
  # Prioridade do dia por (vendedor, cliente) — doc 04/05.4. Saída do
  # Engines::Prioritization: score, fatores decompostos, motivos, potencial,
  # restrições e posição no plano. Regenerada por dia (snapshot do plano).
  def change
    create_table :priorities do |t|
      t.references :salesperson, null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: true
      t.date :reference_date, null: false
      t.decimal :score, precision: 7, scale: 2, null: false, default: 0
      t.jsonb :score_factors, null: false, default: {}   # { fator => { weight:, value:, weighted: } }
      t.jsonb :reasons, null: false, default: []          # [{ key:, label: }] recompra/risco/queda/cross-sell
      t.decimal :potential_value, precision: 15, scale: 2
      t.integer :urgency                                  # 0–100
      t.string :suggested_action
      t.jsonb :restrictions, null: false, default: []     # [{ key:, label: }] bloqueio/inadimplência/pedido aberto…
      t.date :valid_until
      t.integer :position                                 # ordem no plano (1 = mais prioritário)
      t.string :method
      t.string :engine_version
      t.timestamps
    end

    add_index :priorities, %i[salesperson_id reference_date position]
    add_index :priorities, %i[partner_id reference_date]
  end
end
