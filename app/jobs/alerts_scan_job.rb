# Varredura periódica de alertas operacionais (doc 09.14.2). Lógica + guards em
# Alerts::Scan (testável, compartilhado com a rake). Recurring em config/recurring.yml.
class AlertsScanJob < ApplicationJob
  queue_as :default

  def perform
    stats = Alerts::Scan.call
    Rails.logger.info(
      "[AlertsScanJob] #{stats[:firing]} disparando — " \
      "#{stats[:created]} novo(s), #{stats[:updated]} atualizado(s), #{stats[:resolved]} resolvido(s)."
    )
    stats
  end
end
