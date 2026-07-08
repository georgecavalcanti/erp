class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      # Nro. Único — identidade global e estável da nota no ERP (chave de dedupe)
      t.bigint  :external_uid, null: false
      t.integer :invoice_number # Nro. Nota (número fiscal, pode repetir entre séries)
      t.integer :order_number   # Pedido Geral

      t.references :company,      foreign_key: true
      t.references :partner,      foreign_key: true
      t.references :salesperson,  foreign_key: true
      t.references :import_batch, foreign_key: true # último lote que tocou a nota

      t.date    :negotiation_date, null: false          # Dt. Neg.
      t.decimal :total_value, precision: 15, scale: 2, null: false, default: 0 # Vlr. Nota
      t.decimal :commission,  precision: 15, scale: 2, null: false, default: 0 # COMISSÃO

      # Descrições textuais do ERP (guardadas cruas para pivotagens futuras)
      t.string  :payment_terms_raw   # Descrição (Tipo de Negociação)
      t.string  :operation_type_desc # Descrição (Tipo de Operação) -> classifica venda/devolução
      t.string  :nature_desc         # Descrição (Natureza)
      t.string  :result_center_desc  # Descrição (Centro de Resultado)
      t.string  :nfe_status          # Status NF-e
      t.string  :nfse_status         # Status NFS-e
      t.boolean :confirmed, null: false, default: true # Confirmada

      # Classificação venda(0)/devolução(1), derivada do tipo de operação
      t.integer :kind, null: false, default: 0

      # Prazo de pagamento parseado de payment_terms_raw (ex.: [30] ou [30,45])
      t.jsonb   :installment_offsets, null: false, default: []
      t.date    :first_due_date # primeiro vencimento (menor offset)
      t.date    :due_date       # vencimento final / liquidação (maior offset)

      # Controle de pagamento (não vem da planilha — gerido pelo app)
      t.boolean  :paid, null: false, default: false
      t.datetime :paid_at

      # Linha original completa (chaveada pelo cabeçalho) para auditoria/campos futuros
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end

    add_index :invoices, :external_uid, unique: true
    add_index :invoices, :negotiation_date
    add_index :invoices, :kind
    add_index :invoices, %i[negotiation_date kind]
    add_index :invoices, %i[company_id negotiation_date]
    add_index :invoices, %i[salesperson_id negotiation_date]
    add_index :invoices, %i[partner_id negotiation_date]
    add_index :invoices, %i[paid due_date]
  end
end
