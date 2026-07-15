class EnrichPartners < ActiveRecord::Migration[8.1]
  def change
    # Enriquecimento cadastral vindo do TGFPAR (FV360 Sprint 1). Até aqui o
    # parceiro era criado só com código+nome pelo InvoiceWriter; o PartnerSync
    # passa a completar o cadastro de TODOS os clientes (inclusive quem nunca
    # comprou — necessários para carteiras/ativação na Sprint 3).
    change_table :partners, bulk: true do |t|
      t.string :cnpj                                   # CGC_CPF
      t.string :city                                   # TSICID.NOMECID
      t.string :state                                  # TSIUFS.UF (sigla)
      t.string :segment                                # TGFTPP.DESCRTIPPARC (raro hoje)
      t.boolean :active, null: false, default: true    # ATIVO
      t.boolean :blocked, null: false, default: false  # BLOQUEAR = 'S'
      t.string :block_reason                           # MOTBLOQ
      t.date :last_negotiation_on                      # DTULTNEGOC (recência sem varrer notas)
      # Linha original do ERP (inclui CODVEND p/ seed de carteiras e CODTAB p/ preço).
      t.jsonb :raw, null: false, default: {}
    end

    add_index :partners, :active
    add_index :partners, :cnpj
  end
end
