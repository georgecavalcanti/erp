class PartnersExternalCodeToBigint < ActiveRecord::Migration[8.1]
  # Fase 0/Sprint 1 do FV360 revelou 42 clientes reais com CODPARC de 10
  # dígitos (ex.: 6580300236, criados por integração externa no ERP), acima do
  # teto do int4 — o sync pulava esses parceiros (e as notas deles). bigint
  # acompanha o NUMBER do Oracle. `products.external_code` já nasceu bigint.
  def up
    change_column :partners, :external_code, :bigint
  end

  def down
    change_column :partners, :external_code, :integer
  end
end
