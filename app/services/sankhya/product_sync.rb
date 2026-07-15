module Sankhya
  # Sincroniza o catálogo de produtos (TGFPRO + grupo TGFGRU) para Product.
  # Upsert por CODPROD, idempotente; sync FULL a cada execução — o catálogo é
  # pequeno (~3,2 mil produtos, Fase 0), então varrer tudo é mais simples e
  # robusto que incremental por DTALTER (que perderia mudanças só no grupo).
  #
  # Paginação keyset por CODPROD (mesmo padrão do InvoiceSync por NUNOTA):
  # aguenta crescimento do catálogo sem estourar o burstLimit do executeQuery.
  #
  #   Sankhya::ProductSync.new.call                 # grava
  #   Sankhya::ProductSync.new.call(dry_run: true)  # só lê, retorna amostra
  class ProductSync
    PAGE_SIZE = 1000

    def initialize(client: Sankhya::Client.new, page_size: PAGE_SIZE)
      @client = client
      @page_size = page_size
    end

    def call(dry_run: false)
      imported = updated = skipped = seen = 0
      sample = []
      after = -1 # CODPROD 0 pode existir como placeholder — inclui

      loop do
        rows = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if rows.empty?

        rows.each do |row|
          attrs = map(row)
          if dry_run
            sample << attrs if sample.size < 5
            next
          end
          begin
            upsert(attrs) ? imported += 1 : updated += 1
          rescue => e
            # Uma linha ruim não aborta o catálogo inteiro.
            skipped += 1
            Rails.logger.warn("[Sankhya::ProductSync] CODPROD #{attrs[:external_code]} pulado: #{e.message}")
          end
        end

        seen += rows.size
        after = rows.map { |r| r["CODPROD"].to_i }.max
        break if rows.size < @page_size
      end

      { rows: seen, imported: imported, updated: updated, skipped: skipped, sample: sample }
    end

    private

    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT PRO.CODPROD, PRO.DESCRPROD, PRO.CODGRUPOPROD, GRU.DESCRGRUPOPROD,
               PRO.CODVOL, PRO.MARCA, PRO.REFERENCIA, PRO.NCM, PRO.USOPROD,
               PRO.ATIVO, PRO.CODPARCFORN,
               TO_CHAR(PRO.DTALTER, 'YYYY-MM-DD HH24:MI:SS') DTALTER
        FROM TGFPRO PRO
        LEFT JOIN TGFGRU GRU ON GRU.CODGRUPOPROD = PRO.CODGRUPOPROD
        WHERE PRO.CODPROD > #{after.to_i}
        ORDER BY PRO.CODPROD
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def map(row)
      {
        external_code: row["CODPROD"],
        description: row["DESCRPROD"].to_s.strip,
        category_external_code: row["CODGRUPOPROD"],
        category_name: row["DESCRGRUPOPROD"].presence&.strip,
        unit: row["CODVOL"].presence&.strip,
        brand: row["MARCA"].presence&.strip,
        reference: row["REFERENCIA"].presence&.strip,
        ncm: row["NCM"].presence,
        usage: row["USOPROD"].presence,
        active: row["ATIVO"].to_s == "S",
        raw: row
      }
    end

    # true se criou produto novo, false se atualizou existente.
    def upsert(attrs)
      product = Product.find_or_initialize_by(external_code: attrs[:external_code])
      was_new = product.new_record?
      product.assign_attributes(attrs.except(:external_code))
      product.save! if product.changed?
      was_new
    end
  end
end
