class CreateOverdueTitles < ActiveRecord::Migration[8.1]
  def change
    create_table :overdue_titles do |t|
      t.references :import_batch, foreign_key: true
      t.references :salesperson, foreign_key: true          # vínculo best-effort
      t.references :partner, foreign_key: true              # vínculo best-effort por nome
      t.string  :salesperson_label, null: false             # aba de origem (crua)
      t.integer :invoice_number                             # Nro Nota
      t.string  :partner_name                               # Nome Parceiro (cru)
      t.date    :due_date                                   # Dt. Vencimento
      t.decimal :amount, precision: 15, scale: 2, null: false, default: 0 # Vlr
      # open = em aberto (atual) · protested = protestado
      t.integer :category, null: false, default: 0
      t.integer :protest_year                               # ano do protesto (2024/2025/2026)
      t.text    :observation

      t.timestamps
    end

    add_index :overdue_titles, :category
    add_index :overdue_titles, :due_date
    add_index :overdue_titles, :salesperson_label
  end
end
