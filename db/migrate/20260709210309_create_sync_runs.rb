class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.datetime :finished_at, null: false
      t.string :status, null: false          # "ok" | "partial"
      t.jsonb :summary, null: false, default: {}   # contadores por dataset
      t.jsonb :error_messages, null: false, default: []   # mensagens de erro, se houver (não usar :errors — colide com ActiveModel)

      t.timestamps
    end

    add_index :sync_runs, :finished_at
  end
end
