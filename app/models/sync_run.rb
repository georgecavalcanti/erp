# Registro de cada execução real do sync do Sankhya (Sankhya::ScheduledSync).
# Serve de fonte da verdade para "quando o ERP foi sincronizado pela última vez",
# exibido no cabeçalho dos painéis.
class SyncRun < ApplicationRecord
  scope :recent, -> { order(finished_at: :desc) }

  def self.last_run
    recent.first
  end
end
