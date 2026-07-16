class CreateAlerts < ActiveRecord::Migration[8.1]
  # Alertas operacionais (doc 09.14.2). Um job periódico (Alerts::Scan) reavalia as
  # condições e grava/atualiza/resolve alertas. `key` identifica a condição (dedup):
  # no máximo UM alerta aberto por chave (índice parcial único). Quando a condição
  # deixa de ocorrer, o alerta é resolvido (resolved_at).
  #
  #   area:     0 integration · 1 data · 2 reconciliation · 3 business
  #   severity: 0 low · 1 medium · 2 high
  def change
    create_table :alerts do |t|
      t.integer :area, null: false
      t.integer :severity, null: false, default: 1
      t.string :key, null: false                 # condição (ex.: "sync_late", "seller_no_goal:12")
      t.string :title, null: false
      t.text :message
      t.string :entity_type                       # referência frouxa opcional
      t.bigint :entity_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :first_detected_at, null: false
      t.datetime :last_detected_at, null: false
      t.datetime :resolved_at                     # null = aberto
      t.timestamps
    end

    add_index :alerts, %i[area severity]
    add_index :alerts, :resolved_at
    add_index :alerts, :key, unique: true, where: "resolved_at IS NULL", name: "index_alerts_open_unique_key"
  end
end
