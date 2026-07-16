class CreateRepurchasePredictions < ActiveRecord::Migration[8.1]
  # Previsão de recompra por parceiro (doc 04/05.2). Estágio ESTATÍSTICO: data
  # esperada = última compra + MEDIANA do intervalo entre compras; confiança
  # inversamente proporcional à dispersão dos intervalos e proporcional ao nº de
  # ciclos observados. Determinística e versionada (base de auditoria e do
  # aprendizado previsto × real).
  #
  #   level:  0 customer · 1 category · 2 product
  #   status: 0 open · 1 confirmed · 2 missed · 3 canceled
  #
  # Os campos ANALÍTICOS (expected_*, confidence, method) são imutáveis após a
  # gravação; só `status`/`confirmed_invoice_id`/`resolved_at`/`actual_*` mudam
  # in-place — é o laço de aprendizado (compra real cobrindo a previsão).
  def change
    create_table :repurchase_predictions do |t|
      t.references :partner, null: false, foreign_key: true
      t.integer :level, null: false                              # 0 customer · 1 category · 2 product
      t.references :product, foreign_key: true                   # só nível produto
      t.bigint :category_external_code                           # só nível categoria (CODGRUPROD; bigint como em products)
      t.string :category_name                                    # denormalizado p/ exibição
      # Chave do alvo da previsão ("customer" | "category:<cod>" | "product:<id>"):
      # garante 1 previsão ABERTA por (parceiro, alvo) via índice parcial único, e
      # casa a compra real na conciliação.
      t.string :target_key, null: false

      t.date :last_purchase_on                                   # âncora (última compra do alvo)
      t.date :expected_date                                      # âncora + mediana do intervalo
      t.decimal :expected_value, precision: 15, scale: 2         # valor típico da próxima compra
      t.decimal :expected_quantity, precision: 15, scale: 4      # só faz sentido no nível produto
      t.integer :confidence                                      # 0–100
      t.integer :interval_days                                   # mediana do intervalo (dias)
      t.integer :cycles                                          # nº de intervalos observados

      t.string :method
      t.string :engine_version
      t.jsonb :components, null: false, default: {}              # intervalos, média, dispersão, amostra (auditoria)

      t.integer :status, null: false, default: 0                 # 0 open · 1 confirmed · 2 missed · 3 canceled
      t.references :confirmed_invoice, foreign_key: { to_table: :invoices } # compra real que cobriu a previsão
      t.datetime :resolved_at                                    # quando virou confirmed/missed/canceled
      t.date :actual_date                                        # data real da compra (aprendizado)
      t.decimal :actual_value, precision: 15, scale: 2           # valor real da compra (aprendizado)

      t.timestamps
    end

    add_index :repurchase_predictions, %i[partner_id level status]
    add_index :repurchase_predictions, %i[status expected_date] # "recompra atrasada" = open + expected_date < hoje
    # No máximo UMA previsão aberta por (parceiro, alvo) — idempotência do lote noturno.
    add_index :repurchase_predictions, %i[partner_id target_key],
              unique: true, where: "status = 0",
              name: "index_repurchase_open_unique_target"
  end
end
