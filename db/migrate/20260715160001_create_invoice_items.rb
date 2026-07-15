class CreateInvoiceItems < ActiveRecord::Migration[8.1]
  # Itens das notas (TGFITE) — base da análise de mix e margem por produto/nota.
  # Chave natural (NUNOTA, SEQUENCIA); product é opcional (item pode referenciar
  # produto ainda não sincronizado ou já excluído do catálogo).
  #
  # Regra de margem validada na Fase 0 (nota 125075): o desconto do item NÃO
  # está embutido em VLRTOT -> receita líquida = VLRTOT - VLRDESC; custo unitário
  # CUSTO vem congelado na venda -> margem = líquido - (QTDNEG * CUSTO).
  def change
    create_table :invoice_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :product, foreign_key: true                 # nullable de propósito
      t.integer :external_sequence, null: false               # SEQUENCIA
      t.decimal :quantity, precision: 15, scale: 4, default: 0, null: false      # QTDNEG
      t.decimal :unit_price, precision: 15, scale: 6                             # VLRUNIT
      t.decimal :gross_value, precision: 15, scale: 2, default: 0, null: false   # VLRTOT (antes do desconto do item)
      t.decimal :discount_value, precision: 15, scale: 2, default: 0, null: false # VLRDESC
      t.decimal :net_value, precision: 15, scale: 2, default: 0, null: false     # VLRTOT - VLRDESC (bate com VLRNOTA da capa)
      t.decimal :unit_cost, precision: 15, scale: 6                              # CUSTO congelado
      t.decimal :total_cost, precision: 15, scale: 2                            # QTDNEG * CUSTO
      t.decimal :margin_value, precision: 15, scale: 2                          # net_value - total_cost
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end

    add_index :invoice_items, %i[invoice_id external_sequence], unique: true

    # Margem/mix agregados na própria nota (evita recomputar dos itens a cada leitura).
    change_table :invoices, bulk: true do |t|
      t.decimal :total_cost, precision: 15, scale: 2              # Σ itens
      t.decimal :margin_value, precision: 15, scale: 2            # receita líquida - custo
      t.decimal :margin_percent, precision: 7, scale: 4          # margin_value / receita líquida * 100
      t.datetime :items_synced_at                                # quando os itens desta nota foram espelhados
    end
  end
end
