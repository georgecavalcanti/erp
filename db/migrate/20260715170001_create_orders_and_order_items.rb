class CreateOrdersAndOrderItems < ActiveRecord::Migration[8.1]
  # Histórico PERSISTENTE de pedidos de venda (TOP 1001), upsert por NUNOTA —
  # base analítica para projeção (pedidos pendentes ponderados) e cross-sell.
  #
  # Difere de `pending_orders` (snapshot só da carteira do mês corrente, que
  # segue alimentando a tela Carteira): `orders` guarda TODO pedido, de qualquer
  # mês, com o status derivado do par (STATUSNOTA, PENDENTE) mapeado na Fase 0:
  #   L + PENDENTE=S -> pending (a faturar)   |   A + S -> awaiting (aguardando lib.)
  #   PENDENTE=N     -> billed (faturado)     |   cancelado some do ERP (reconcile futuro)
  #
  # A consolidação pending_orders -> orders.pending fica para quando as telas de
  # carteira forem reformuladas (FV360 Sprints 5+).
  def change
    create_table :orders do |t|
      t.bigint :external_uid, null: false            # NUNOTA
      t.integer :order_number                        # NUNOTA (nº do pedido)
      t.references :company, foreign_key: true
      t.references :partner, foreign_key: true
      t.references :salesperson, foreign_key: true
      t.string :partner_name                         # denormalizado (fallback do ERP)
      t.string :salesperson_label
      t.date :negotiation_date
      t.date :movement_date
      t.decimal :total_value, precision: 15, scale: 2, default: 0, null: false
      t.integer :status, null: false, default: 0     # enum pending/awaiting/billed
      t.string :note_status                          # STATUSNOTA cru (L/A)
      t.boolean :pending, null: false, default: true # PENDENTE cru
      t.string :delivery_type                        # CIF_FOB
      t.decimal :total_cost, precision: 15, scale: 2      # Σ itens
      t.decimal :margin_value, precision: 15, scale: 2
      t.decimal :margin_percent, precision: 7, scale: 4
      t.datetime :items_synced_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :orders, :external_uid, unique: true
    add_index :orders, :status
    add_index :orders, %i[salesperson_id status]   # carteira por vendedor

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.integer :external_sequence, null: false
      t.decimal :quantity, precision: 15, scale: 4, default: 0, null: false
      t.decimal :unit_price, precision: 15, scale: 6
      t.decimal :gross_value, precision: 15, scale: 2, default: 0, null: false
      t.decimal :discount_value, precision: 15, scale: 2, default: 0, null: false
      t.decimal :net_value, precision: 15, scale: 2, default: 0, null: false
      t.decimal :unit_cost, precision: 15, scale: 6
      t.decimal :total_cost, precision: 15, scale: 2
      t.decimal :margin_value, precision: 15, scale: 2
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :order_items, %i[order_id external_sequence], unique: true
  end
end
