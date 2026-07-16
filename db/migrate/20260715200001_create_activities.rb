class CreateActivities < ActiveRecord::Migration[8.1]
  # Registro de relacionamento com o cliente (doc 04): contato/visita/tarefa/
  # observação/resultado. Alimenta o Cliente 360 e, adiante, o motor de risco
  # ("sem contato há N dias") e a receita influenciada.
  #
  #   kind: 0 contact · 1 visit · 2 task · 3 note · 4 result
  def change
    create_table :activities do |t|
      t.references :user, null: false, foreign_key: true        # quem registrou
      t.references :salesperson, foreign_key: true
      t.references :partner, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.string :channel                                         # call/whatsapp/visit/email/internal
      t.text :notes
      t.datetime :occurred_at, null: false
      t.bigint :recommendation_id                               # FK só na Sprint 7 (recommendations ainda não existe)
      t.jsonb :outcome, null: false, default: {}
      t.timestamps
    end

    add_index :activities, %i[partner_id occurred_at]
    add_index :activities, %i[salesperson_id occurred_at]
  end
end
