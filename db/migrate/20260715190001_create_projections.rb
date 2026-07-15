class CreateProjections < ActiveRecord::Migration[8.1]
  # Projeção de faturamento do mês por vendedor (doc 04/05.1). APPEND-ONLY: cada
  # recálculo relevante grava uma nova leva (3 linhas, uma por cenário), nunca
  # sobrescreve — é a base de auditoria e de acurácia (previsto × realizado).
  #
  #   scenario: 0 conservative · 1 likely · 2 potential
  def change
    create_table :projections do |t|
      t.references :salesperson, null: false, foreign_key: true
      t.date :reference_date, null: false                        # "as of" (dia do recálculo)
      t.integer :scenario, null: false
      t.decimal :value, precision: 15, scale: 2, default: 0, null: false # projeção líquida
      t.decimal :margin_value, precision: 15, scale: 2
      t.decimal :target_value, precision: 15, scale: 2           # meta do mês (snapshot)
      t.decimal :realized_value, precision: 15, scale: 2         # realizado até reference_date
      t.decimal :gap_value, precision: 15, scale: 2              # meta − projeção
      t.integer :confidence                                      # 0–100
      t.jsonb :components, null: false, default: {}              # parcelas rastreáveis + dias úteis
      t.string :method
      t.string :engine_version
      t.timestamps
    end

    add_index :projections, %i[salesperson_id reference_date scenario]
    add_index :projections, :reference_date
  end
end
