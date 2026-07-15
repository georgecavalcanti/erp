module Sankhya
  # Enriquece o cadastro de parceiros a partir do TGFPAR (+ cidade/UF/tipo).
  # Escopo: TODOS os clientes (CLIENTE = 'S'), ativos ou não — inclusive quem
  # nunca comprou, porque carteiras/ativação (Sprint 3) precisam deles. Quem só
  # existe em nota (transportadora etc.) segue criado pelo InvoiceWriter com
  # código+nome e não é enriquecido aqui.
  #
  # Upsert por CODPARC, full a cada execução (~6 mil clientes = 6 páginas).
  # NÃO sobrescreve `name` com vazio e não toca nos campos que o InvoiceWriter
  # gerencia. `raw` guarda a linha (CODVEND -> seed de carteiras; CODTAB -> preço).
  class PartnerSync
    PAGE_SIZE = 1000

    def initialize(client: Sankhya::Client.new, page_size: PAGE_SIZE)
      @client = client
      @page_size = page_size
    end

    def call(dry_run: false)
      imported = updated = skipped = seen = 0
      sample = []
      after = 0 # CODPARC 0 = "<SEM PARCEIRO>" — placeholder do ERP, fora

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
            skipped += 1
            Rails.logger.warn("[Sankhya::PartnerSync] CODPARC #{attrs[:external_code]} pulado: #{e.message}")
          end
        end

        seen += rows.size
        after = rows.map { |r| r["CODPARC"].to_i }.max
        break if rows.size < @page_size
      end

      { rows: seen, imported: imported, updated: updated, skipped: skipped, sample: sample }
    end

    private

    # TSICID.UF guarda o CÓDIGO da UF (int) -> sigla via TSIUFS (Fase 0 §9).
    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT PAR.CODPARC, PAR.NOMEPARC, PAR.RAZAOSOCIAL, PAR.CGC_CPF,
               PAR.ATIVO, PAR.BLOQUEAR, PAR.MOTBLOQ, PAR.CODVEND, PAR.CODTAB,
               PAR.AD_CURVA, TO_CHAR(PAR.DTULTNEGOC, 'YYYY-MM-DD') DTULTNEGOC,
               CID.NOMECID, UFS.UF, TPP.DESCRTIPPARC
        FROM TGFPAR PAR
        LEFT JOIN TSICID CID ON CID.CODCID = PAR.CODCID
        LEFT JOIN TSIUFS UFS ON UFS.CODUF = CID.UF
        LEFT JOIN TGFTPP TPP ON TPP.CODTIPPARC = PAR.CODTIPPARC
        WHERE PAR.CLIENTE = 'S' AND PAR.CODPARC > #{after.to_i}
        ORDER BY PAR.CODPARC
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def map(row)
      {
        external_code: row["CODPARC"],
        name: row["NOMEPARC"].to_s.strip,
        cnpj: row["CGC_CPF"].presence,
        city: row["NOMECID"].presence&.strip,
        state: row["UF"].presence&.strip,
        segment: row["DESCRTIPPARC"].presence&.strip,
        active: row["ATIVO"].to_s == "S",
        blocked: row["BLOQUEAR"].to_s == "S",
        block_reason: row["MOTBLOQ"].presence,
        last_negotiation_on: parse_date(row["DTULTNEGOC"]),
        raw: row
      }
    end

    def upsert(attrs)
      partner = Partner.find_or_initialize_by(external_code: attrs[:external_code])
      was_new = partner.new_record?
      # Nome: ERP manda; só não regride para vazio (validação exige presença).
      attrs = attrs.except(:name) if attrs[:name].blank?
      partner.assign_attributes(attrs.except(:external_code))
      partner.save! if partner.changed?
      was_new
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
