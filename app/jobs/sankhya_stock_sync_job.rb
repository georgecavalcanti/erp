# Snapshot de estoque (recurring 30 min em horário comercial, ver config/recurring.yml).
class SankhyaStockSyncJob < ApplicationJob
  queue_as :sankhya

  def perform
    result = Sankhya::StockSync.new.call
    Rails.logger.info("[SankhyaStockSyncJob] estoque: #{result.except(:sample).inspect}")
  end
end
