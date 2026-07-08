class CreateSalespeople < ActiveRecord::Migration[8.1]
  def change
    create_table :salespeople do |t|
      # Código do vendedor no ERP (coluna "Vendedor")
      t.integer :external_code, null: false
      # Apelido (Vendedor)
      t.string :nickname, null: false

      t.timestamps
    end

    add_index :salespeople, :external_code, unique: true
    add_index :salespeople, :nickname
  end
end
