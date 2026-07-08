class CreatePendingOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_orders do |t|
      t.bigint  :external_uid, null: false        # Nro. Nota (número do pedido no ERP)
      t.integer :order_number                      # mesmo número, para referência

      t.references :company,      foreign_key: true
      t.references :partner,      foreign_key: true
      t.references :salesperson,  foreign_key: true
      t.references :import_batch, foreign_key: true
      # O pedido pendente traz só nomes (sem código de parceiro/vendedor).
      t.string  :partner_name
      t.string  :salesperson_label

      t.date    :negotiation_date                  # Dt. Neg.
      t.date    :movement_date                     # Dt. do Movimento
      t.decimal :total_value, precision: 15, scale: 2, null: false, default: 0 # Vlr. Nota
      t.decimal :commission,  precision: 15, scale: 2, null: false, default: 0

      t.string  :operation_type_desc               # "PEDIDO DE VENDA PRIVADO"
      t.string  :note_status                       # Status da Nota ("Liberada")
      t.string  :delivery_type                     # Retira/Entrega
      t.boolean :pending, null: false, default: true
      t.boolean :printed, null: false, default: false # "Pedido foi impresso?"

      t.jsonb   :raw, null: false, default: {}

      t.timestamps
    end

    add_index :pending_orders, :external_uid
    add_index :pending_orders, :negotiation_date
    add_index :pending_orders, %i[salesperson_id negotiation_date]
  end
end
