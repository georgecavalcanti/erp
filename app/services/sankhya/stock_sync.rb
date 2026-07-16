module Sankhya
  # Snapshot de estoque (TGFEST, empresa 1, local padrão 10100 — Fase 0). É ESTADO,
  # não histórico: substitui o conjunto inteiro de forma atômica (delete + insert),
  # como o PendingOrderSync. Colunas: ESTOQUE (físico), RESERVADO, WMSBLOQUEADO.
  #
  # Guard de janela vazia: se a API não trouxe linha, NÃO zera o snapshot (evita
  # sumir com o estoque por uma falha) — mantém o último e sinaliza.
  #
  #   Sankhya::StockSync.new.call
  class StockSync
    COMPANIES = [ 1 ].freeze
    LOCAL = 10_100
    PAGE_SIZE = 2000

    def initialize(client: Sankhya::Client.new, page_size: PAGE_SIZE)
      @client = client
      @page_size = page_size
    end

    def call(dry_run: false)
      rows = fetch_all
      products = Product.pluck(:external_code, :id).to_h
      now = Time.current

      records = rows.filter_map do |row|
        product_id = products[row["CODPROD"].to_i]
        next if product_id.nil? # estoque de produto sem cadastro local

        {
          product_id: product_id,
          on_hand: to_d(row["ESTOQUE"]), reserved: to_d(row["RESERVADO"]), blocked: to_d(row["WMSBLOQUEADO"]),
          synced_at: now, created_at: now, updated_at: now
        }
      end

      result = { rows: rows.size, stored: records.size, missing_product: rows.size - records.size,
                 sample: dry_run ? records.first(5) : [] }
      return result.merge(skipped: :empty_window) if !dry_run && rows.empty? # não zera por falha
      return result if dry_run

      StockLevel.transaction do
        StockLevel.delete_all
        StockLevel.insert_all(records) if records.any?
      end
      result
    end

    private

    def fetch_all
      all = []
      after = 0
      loop do
        page = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if page.empty?

        all.concat(page)
        after = page.map { |r| r["CODPROD"].to_i }.max
        break if page.size < @page_size
      end
      all
    end

    # SUM + GROUP BY CODPROD: um produto pode ter várias linhas em TGFEST no mesmo
    # local (lotes/localizações/controle). Somar dá o estoque real do produto —
    # sem o GROUP BY, o índice único deixaria só uma linha e subcontaria.
    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT EST.CODPROD,
               SUM(EST.ESTOQUE) ESTOQUE, SUM(EST.RESERVADO) RESERVADO, SUM(EST.WMSBLOQUEADO) WMSBLOQUEADO
        FROM TGFEST EST
        WHERE EST.CODEMP IN (#{COMPANIES.join(',')})
          AND EST.CODLOCAL = #{LOCAL}
          AND EST.CODPROD > #{after.to_i}
        GROUP BY EST.CODPROD
        ORDER BY EST.CODPROD
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def to_d(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal(0)
    end
  end
end
