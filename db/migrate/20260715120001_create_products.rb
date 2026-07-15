class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    # Espelho do catálogo do Sankhya (TGFPRO + grupo TGFGRU). Dimensão central
    # do FV360: itens de nota/pedido, estoque, custo e preço apontam para cá.
    # CODPROD real chega perto do teto de int4 (ex.: 1815629523) -> bigint.
    create_table :products do |t|
      t.bigint :external_code, null: false            # CODPROD
      t.string :description, null: false              # DESCRPROD
      t.bigint :category_external_code                # CODGRUPOPROD (TGFGRU)
      t.string :category_name                         # DESCRGRUPOPROD
      t.string :unit                                  # CODVOL (UN, CX, FD...)
      t.string :brand                                 # MARCA (pouco preenchida hoje)
      t.string :reference                             # REFERENCIA
      t.string :ncm                                   # NCM
      t.string :usage                                 # USOPROD ('R' = revenda)
      t.boolean :active, null: false, default: true   # ATIVO
      # Custo gerencial vigente (TGFCUS.CUSGER) — preenchido pelo CostSync (Sprint 2).
      t.decimal :current_cost, precision: 15, scale: 5
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end

    add_index :products, :external_code, unique: true
    add_index :products, :category_external_code
    add_index :products, :active
  end
end
