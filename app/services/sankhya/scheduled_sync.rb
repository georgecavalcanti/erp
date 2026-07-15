module Sankhya
  # Orquestra o sync agendado: incremental de notas + snapshots de carteira e
  # inadimplência. Resiliente (cada dataset falha isolado — um erro de API nas
  # Notas não derruba Carteira/Inadimplência) e protegido por advisory lock, que
  # evita runs sobrepostos entre si OU com a rake task `sankhya:sync` rodada à mão.
  #
  # Compartilhado por lib/tasks/sankhya.rake e por SankhyaSyncJob (recurring).
  class ScheduledSync
    LOCK_KEY = 84_720_001 # id arbitrário do advisory lock deste job

    class PartialFailure < StandardError; end

    def self.call
      new.call
    end

    # => { skipped:, results: { "Notas" => {...}, ... }, errors: [ "..." ] }
    def call
      conn = ActiveRecord::Base.connection
      unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
        return { skipped: true, results: {}, errors: [] }
      end

      results = {}
      errors = []
      begin
        steps.each do |label, step|
          results[label] = step.call
        rescue => e
          errors << "#{label}: #{e.class} — #{e.message}"
        end
      ensure
        conn.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})")
      end

      record_run(results, errors)
      { skipped: false, results: results, errors: errors }
    end

    private

    # Registra a execução (fonte do "último sync" exibido nos painéis). Nunca
    # derruba o sync: um erro ao gravar o histórico é logado e ignorado.
    def record_run(results, errors)
      SyncRun.create!(
        finished_at: Time.current,
        status: errors.empty? ? "ok" : "partial",
        summary: results.transform_values { |r| r.is_a?(Hash) ? r.except(:sample) : r },
        error_messages: errors
      )
    rescue => e
      Rails.logger.error("[ScheduledSync] falha ao registrar SyncRun: #{e.class} — #{e.message}")
    end

    # Janela de 24h no incremental cobre o intervalo noturno, garantindo que
    # mudanças entre a última rodada de um dia e a 1ª do dia seguinte não escapem.
    def steps
      {
        "Notas" => -> { Sankhya::InvoiceSync.new(changed_within_hours: 24).call },
        "Carteira" => -> { Sankhya::PendingOrderSync.new.call },
        "Inadimplência" => -> { Sankhya::OverdueTitleSync.new.call },
        # Itens das notas mexidas nas últimas 24h -> recomputa a margem delas.
        # Depende das Notas já terem entrado nesta rodada (mesmo horizonte).
        "Itens" => -> { Sankhya::InvoiceItemSync.new(changed_within_hours: 24).call },
        # Histórico de pedidos (status) + seus itens, mesma janela.
        "Pedidos" => -> { Sankhya::OrderSync.new(changed_within_hours: 24).call },
        "ItensPedido" => -> { Sankhya::OrderItemSync.new(changed_within_hours: 24).call }
      }
    end
  end
end
