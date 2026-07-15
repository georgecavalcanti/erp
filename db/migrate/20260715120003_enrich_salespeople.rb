class EnrichSalespeople < ActiveRecord::Migration[8.1]
  def change
    # Enriquecimento do vendedor vindo do TGFVEN (FV360 Sprint 1).
    # seller_kind = TIPVEND: 'V' vendedor, 'C' comprador, 'G' gerente — a UI de
    # carteiras/metas filtra por 'V'. email fica pronto para o vínculo com User
    # (Sprint 3), embora vazio no ERP hoje (diagnóstico Fase 0).
    change_table :salespeople, bulk: true do |t|
      t.boolean :active, null: false, default: true # ATIVO
      t.string :email                               # EMAIL
      t.string :seller_kind                         # TIPVEND
      t.jsonb :raw, null: false, default: {}
    end

    add_index :salespeople, :active
  end
end
