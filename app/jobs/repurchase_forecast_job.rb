# Lote noturno de recompra (doc 05.2). Para cada parceiro COM DONO (carteira
# vigente — alguém vai agir sobre a previsão), na ordem certa:
#
#   1. reconcile!  concilia as abertas com a realidade (compra real → confirmed;
#                  vencida sem compra nem pedido → missed) — ANTES de gerar novas,
#                  para a compra que chegou fechar a previsão do ciclo anterior.
#   2. persist!    grava as previsões abertas do ciclo atual (idempotente).
#
# Determinístico e sem IA. Só produção (config/recurring.yml, madrugada) — em
# dev/test roda sob demanda pela rake/pelo teste.
class RepurchaseForecastJob < ApplicationJob
  queue_as :default

  def perform(partner_id = nil)
    scope =
      if partner_id
        Partner.where(id: partner_id)
      else
        Partner.where(id: Wallet.active.select(:partner_id))
      end

    stats = { partners: 0, confirmed: 0, missed: 0, created: 0 }
    scope.find_each do |partner|
      engine = Engines::Repurchase.new(partner)
      resolved = engine.reconcile!
      created = engine.persist!
      stats[:partners] += 1
      stats[:confirmed] += resolved[:confirmed]
      stats[:missed] += resolved[:missed]
      stats[:created] += created.size
    rescue StandardError => e
      Rails.logger.error("[RepurchaseForecastJob] parceiro #{partner.id} falhou: #{e.class}: #{e.message}")
    end
    Rails.logger.info(
      "[RepurchaseForecastJob] #{stats[:partners]} parceiro(s): " \
      "#{stats[:created]} nova(s), #{stats[:confirmed]} confirmada(s), #{stats[:missed]} perdida(s)."
    )
    stats
  end
end
