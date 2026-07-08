class CreateDelinquencies < ActiveRecord::Migration[8.1]
  def change
    create_table :delinquencies do |t|
      t.references :import_batch, foreign_key: true
      t.references :salesperson, foreign_key: true # vínculo best-effort
      t.string  :salesperson_label, null: false    # VENDEDOR (cru, da planilha)

      t.decimal :open_total,      precision: 15, scale: 2, null: false, default: 0 # TOTAL (em aberto)
      t.decimal :protested_2024,  precision: 15, scale: 2, null: false, default: 0
      t.decimal :protested_2025,  precision: 15, scale: 2, null: false, default: 0
      t.decimal :protested_2026,  precision: 15, scale: 2, null: false, default: 0
      t.decimal :saldo_reported,  precision: 15, scale: 2                          # SALDO DEVEDOR da planilha (referência)

      t.timestamps
    end

    add_index :delinquencies, :salesperson_label
  end
end
