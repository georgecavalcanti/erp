# Trilha de exportações (doc 09): exportar dados exige perfil gestor+ e é
# REGISTRADO (quem, o quê, quantas linhas, com quais filtros e quando).
class CreateExportLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :export_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false          # "equipe", "custo_agente", ...
      t.string :format, null: false, default: "csv"
      t.integer :row_count, null: false, default: 0
      t.jsonb :filters, null: false, default: {} # recorte aplicado (mês, escopo)
      t.timestamps
    end

    add_index :export_logs, %i[kind created_at]
  end
end
