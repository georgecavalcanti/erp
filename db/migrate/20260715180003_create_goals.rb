class CreateGoals < ActiveRecord::Migration[8.1]
  # Meta por vendedor/período (doc 04). O ERP não gere metas (TGFMET vazia, Fase 0)
  # → cadastro é do FV360, feito pelo gestor/admin. Uma meta por (vendedor, mês,
  # tipo). `period` é sempre o 1º dia do mês.
  #
  #   kind: 0 revenue (faturamento) · 1 margin (margem) · 2 mix · 3 activation (ativação)
  def change
    create_table :goals do |t|
      t.references :salesperson, null: false, foreign_key: true
      t.date :period, null: false                          # 1º dia do mês
      t.integer :kind, null: false, default: 0
      t.decimal :amount, precision: 15, scale: 2           # alvo (R$ p/ revenue; % fica em min_margin_percent)
      t.decimal :min_margin_percent, precision: 7, scale: 4
      t.jsonb :complementary, null: false, default: {}     # parâmetros extras por tipo
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :goals, %i[salesperson_id period kind], unique: true
    add_index :goals, :period
  end
end
