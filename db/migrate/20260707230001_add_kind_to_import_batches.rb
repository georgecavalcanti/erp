class AddKindToImportBatches < ActiveRecord::Migration[8.1]
  def change
    # invoices = Cabeçalho da Nota (vendas + devoluções) · delinquency = inadimplência
    add_column :import_batches, :kind, :integer, null: false, default: 0
    # Data de referência do snapshot (ex.: "até 06/07/26" da inadimplência)
    add_column :import_batches, :reference_date, :date
  end
end
