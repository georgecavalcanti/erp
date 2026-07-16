class CreateStockLevels < ActiveRecord::Migration[8.1]
  # Estoque por produto (TGFEST, Fase 0: empresa 1, local padrão 10100). SNAPSHOT
  # atômico (delete+insert), como PendingOrderSync — é estado, não histórico.
  # Colunas do ERP: ESTOQUE (físico), RESERVADO, WMSBLOQUEADO.
  # Disponível para venda = físico − reservado − bloqueado (StockLevel#sellable).
  def change
    create_table :stock_levels do |t|
      # um nível por produto (empresa 1, local padrão) → índice único na própria referência
      t.references :product, null: false, foreign_key: true, index: { unique: true }
      t.references :company, foreign_key: true
      t.decimal :on_hand, precision: 15, scale: 4, default: 0, null: false   # ESTOQUE
      t.decimal :reserved, precision: 15, scale: 4, default: 0, null: false   # RESERVADO
      t.decimal :blocked, precision: 15, scale: 4, default: 0, null: false    # WMSBLOQUEADO
      t.datetime :synced_at, null: false
      t.timestamps
    end
  end
end
