# Reconcile agendado das notas (recurring via Solid Queue, ver config/recurring.yml).
# Fecha o ponto cego do upsert (nota deletada/estornada no ERP vira órfã local).
# Lógica + guards em Sankhya::Reconcile, compartilhado com a rake task.
class SankhyaReconcileJob < ApplicationJob
  queue_as :sankhya

  def perform(days = 90)
    r = Sankhya::Reconcile.call(days: days)
    Rails.logger.info(
      "[SankhyaReconcileJob] #{r[:days]}d: #{r[:read]} lidas, #{r[:removed]} órfã(s) removida(s)."
    )
  end
end
