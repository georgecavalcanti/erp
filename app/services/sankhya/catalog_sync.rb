module Sankhya
  # Orquestra o sync de CADASTROS (produtos, parceiros, vendedores) — mudam
  # devagar, então rodam a cada 2h (config/recurring.yml), separados do sync
  # transacional de 30min (ScheduledSync: notas/carteira/inadimplência).
  #
  # Mesmo desenho resiliente do ScheduledSync: cada dataset falha isolado,
  # advisory lock próprio (não disputa com o transacional — podem coexistir)
  # e registro em SyncRun.
  #
  # Compartilhado por lib/tasks/sankhya.rake e por SankhyaCatalogSyncJob.
  class CatalogSync
    LOCK_KEY = 84_720_002 # id arbitrário do advisory lock deste job (ScheduledSync usa ...001)

    def self.call
      new.call
    end

    # => { skipped:, results: { "Produtos" => {...}, ... }, errors: [ "..." ] }
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

    def record_run(results, errors)
      SyncRun.create!(
        finished_at: Time.current,
        status: errors.empty? ? "ok" : "partial",
        summary: results.transform_values { |r| r.is_a?(Hash) ? r.except(:sample) : r },
        error_messages: errors
      )
    rescue => e
      Rails.logger.error("[CatalogSync] falha ao registrar SyncRun: #{e.class} — #{e.message}")
    end

    def steps
      {
        "Produtos" => -> { Sankhya::ProductSync.new.call },
        "Parceiros" => -> { Sankhya::PartnerSync.new.call },
        "Vendedores" => -> { Sankhya::SalespersonSync.new.call }
      }
    end
  end
end
