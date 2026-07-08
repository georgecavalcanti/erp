class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      # Código da empresa no ERP (coluna "Empresa")
      t.integer :external_code, null: false
      # Nome Fantasia (Empresa)
      t.string :name, null: false

      t.timestamps
    end

    add_index :companies, :external_code, unique: true
  end
end
