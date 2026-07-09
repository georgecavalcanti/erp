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

      { skipped: false, results: results, errors: errors }
    end

    private

    # Janela de 24h no incremental cobre o intervalo noturno, garantindo que
    # mudanças entre a última rodada de um dia e a 1ª do dia seguinte não escapem.
    def steps
      {
        "Notas" => -> { Sankhya::InvoiceSync.new(changed_within_hours: 24).call },
        "Carteira" => -> { Sankhya::PendingOrderSync.new.call },
        "Inadimplência" => -> { Sankhya::OverdueTitleSync.new.call }
      }
    end
  end
end
