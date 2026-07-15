# Sync agendado do Sankhya (recurring via Solid Queue, ver config/recurring.yml).
# A orquestração resiliente + advisory lock vivem em Sankhya::ScheduledSync,
# compartilhado com a rake task `sankhya:sync`.
class SankhyaSyncJob < ApplicationJob
  queue_as :sankhya

  def perform
    result = Sankhya::ScheduledSync.call

    if result[:skipped]
      Rails.logger.info("[SankhyaSyncJob] pulado: outra execução em andamento (advisory lock).")
      return
    end

    result[:results].each do |label, res|
      Rails.logger.info("[SankhyaSyncJob] #{label}: #{res.except(:sample).inspect}")
    end

    # Sync relevante muda realizado/carteira → reprojeta (append-only, sem IA).
    ProjectionRecalcJob.perform_later

    return if result[:errors].empty?

    # Falha visível no Solid Queue (failed_executions); a próxima rodada recupera.
    raise Sankhya::ScheduledSync::PartialFailure, result[:errors].join(" | ")
  end
end
