class CreateInfluencedRevenues < ActiveRecord::Migration[8.1]
  # Receita influenciada (doc 04): liga uma recomendação à nota que ela gerou —
  # base do indicador do piloto. `registrar resultado` no Plano do Dia cria o
  # vínculo (linked_by = manual); a conciliação automática vem depois.
  #
  #   linked_by: 0 automatic · 1 manual
  def change
    create_table :influenced_revenues do |t|
      t.references :recommendation, null: false, foreign_key: true
      t.references :invoice, foreign_key: true
      t.decimal :amount, precision: 15, scale: 2
      t.integer :linked_by, null: false, default: 1
      t.timestamps
    end

    add_index :influenced_revenues, %i[recommendation_id invoice_id], unique: true
  end
end
