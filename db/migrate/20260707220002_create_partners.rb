class CreatePartners < ActiveRecord::Migration[8.1]
  def change
    create_table :partners do |t|
      # Código do parceiro/cliente no ERP (coluna "Parceiro")
      t.integer :external_code, null: false
      # Nome Parceiro (Parceiro)
      t.string :name, null: false

      t.timestamps
    end

    add_index :partners, :external_code, unique: true
    add_index :partners, :name
  end
end
