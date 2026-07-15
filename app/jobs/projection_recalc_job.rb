# Recalcula e PERSISTE (append-only) a projeção do mês. Alvo: vendedores COM META
# no mês corrente — a projeção é acionável em relação a uma meta (sem meta, o
# Cockpit ainda calcula ao vivo, mas não vale a pena versionar). Determinístico e
# sem IA. Dispara na virada do dia (config/recurring.yml) e após um sync relevante.
class ProjectionRecalcJob < ApplicationJob
  queue_as :default

  def perform(salesperson_id = nil)
    scope =
      if salesperson_id
        Salesperson.where(id: salesperson_id)
      else
        Salesperson.where(id: Goal.for_period(Date.current).distinct.select(:salesperson_id))
      end

    persisted = 0
    scope.find_each do |salesperson|
      Engines::Projection.new(salesperson).persist!
      persisted += 1
    rescue StandardError => e
      Rails.logger.error("[ProjectionRecalcJob] vendedor #{salesperson.id} falhou: #{e.class}: #{e.message}")
    end
    Rails.logger.info("[ProjectionRecalcJob] #{persisted} vendedor(es) reprojetado(s).")
    persisted
  end
end
