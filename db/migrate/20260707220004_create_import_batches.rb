class CreateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :import_batches do |t|
      t.references :user, foreign_key: true
      t.string  :original_filename, null: false
      # enum: pending / processing / completed / failed
      t.integer :status, null: false, default: 0
      t.integer :rows_total,    null: false, default: 0
      t.integer :rows_imported, null: false, default: 0 # novas notas
      t.integer :rows_updated,  null: false, default: 0 # notas já existentes atualizadas
      t.integer :rows_skipped,  null: false, default: 0 # linhas ignoradas (totais, vazias)
      t.text    :error_message
      # Faixa de datas de negociação encontrada no arquivo
      t.date    :period_start
      t.date    :period_end

      t.timestamps
    end
  end
end
