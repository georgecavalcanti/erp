class CreatePrioritySettings < ActiveRecord::Migration[8.1]
  # Configuração do motor de priorização (doc 05.4): pesos dos fatores do score,
  # capacidade diária e limiares das restrições. Editável pelo gestor. É um
  # SINGLETON (uma linha global no MVP) — PriorityConfig.current cai nos defaults
  # do doc quando não há linha.
  #
  # Pesos iniciais (doc 05.4): receita 25 · conversão 20 · urgência 15 · gap 15 ·
  # risco 10 · margem 10 · estratégico 5 (somam 100).
  def change
    create_table :priority_settings do |t|
      t.integer :weight_revenue, null: false, default: 25
      t.integer :weight_conversion, null: false, default: 20
      t.integer :weight_urgency, null: false, default: 15
      t.integer :weight_gap, null: false, default: 15
      t.integer :weight_risk, null: false, default: 10
      t.integer :weight_margin, null: false, default: 10
      t.integer :weight_strategic, null: false, default: 5

      t.integer :daily_capacity, null: false, default: 12       # nº de ações/dia no plano
      t.integer :recent_contact_days, null: false, default: 3   # contato há ≤ N dias = restrição
      t.decimal :min_margin_percent, precision: 7, scale: 2      # margem histórica abaixo = restrição (null = sem)

      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
