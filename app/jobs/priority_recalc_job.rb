# Recalcula e PERSISTE o plano do dia (priorities + recommendations) por vendedor
# com carteira vigente. Determinístico, sem IA. Roda de manhã cedo (após a
# recompra da madrugada) — config/recurring.yml. Só produção.
class PriorityRecalcJob < ApplicationJob
  queue_as :default

  def perform(salesperson_id = nil)
    scope =
      if salesperson_id
        Salesperson.where(id: salesperson_id)
      else
        Salesperson.where(id: Wallet.active.select(:salesperson_id))
      end

    planned = 0
    scope.find_each do |salesperson|
      Engines::Prioritization.new(salesperson).persist!
      planned += 1
    rescue StandardError => e
      Rails.logger.error("[PriorityRecalcJob] vendedor #{salesperson.id} falhou: #{e.class}: #{e.message}")
    end
    Rails.logger.info("[PriorityRecalcJob] plano do dia gerado para #{planned} vendedor(es).")
    planned
  end
end
