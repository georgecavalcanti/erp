# Sync agendado de cadastros (produtos/parceiros/vendedores) — recurring via
# Solid Queue, ver config/recurring.yml. Orquestração em Sankhya::CatalogSync,
# compartilhada com a rake task `sankhya:sync_catalog`.
class SankhyaCatalogSyncJob < ApplicationJob
  queue_as :sankhya

  def perform
    result = Sankhya::CatalogSync.call

    if result[:skipped]
      Rails.logger.info("[SankhyaCatalogSyncJob] pulado: outra execução em andamento (advisory lock).")
      return
    end

    result[:results].each do |label, res|
      Rails.logger.info("[SankhyaCatalogSyncJob] #{label}: #{res.except(:sample).inspect}")
    end
    return if result[:errors].empty?

    raise Sankhya::ScheduledSync::PartialFailure, result[:errors].join(" | ")
  end
end
