module Sankhya
  # Enriquece o cadastro de vendedores a partir do TGFVEN (60 linhas — uma
  # página resolve, allow_burst). Upsert por CODVEND. seller_kind = TIPVEND
  # ('V' vendedor, 'C' comprador, 'G' gerente) permite às telas do FV360
  # listarem só vendedores de verdade. raw guarda CODGER/PARTICMETA p/ futuro.
  class SalespersonSync
    def initialize(client: Sankhya::Client.new)
      @client = client
    end

    def call(dry_run: false)
      rows = @client.execute_query(sql, allow_burst: true)
      imported = updated = skipped = 0
      sample = []

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
          Rails.logger.warn("[Sankhya::SalespersonSync] CODVEND #{attrs[:external_code]} pulado: #{e.message}")
        end
      end

      { rows: rows.size, imported: imported, updated: updated, skipped: skipped, sample: sample }
    end

    private

    def sql
      <<~SQL.squish
        SELECT VEN.CODVEND, VEN.APELIDO, VEN.ATIVO, VEN.EMAIL, VEN.TIPVEND,
               VEN.CODGER, VEN.CODEMP, VEN.CODPARC, VEN.PARTICMETA
        FROM TGFVEN VEN
        ORDER BY VEN.CODVEND
      SQL
    end

    def map(row)
      {
        external_code: row["CODVEND"],
        nickname: row["APELIDO"].to_s.strip,
        active: row["ATIVO"].to_s == "S",
        email: row["EMAIL"].presence&.strip&.downcase,
        seller_kind: row["TIPVEND"].presence,
        raw: row
      }
    end

    def upsert(attrs)
      seller = Salesperson.find_or_initialize_by(external_code: attrs[:external_code])
      was_new = seller.new_record?
      attrs = attrs.except(:nickname) if attrs[:nickname].blank?
      seller.assign_attributes(attrs.except(:external_code))
      seller.save! if seller.changed?
      was_new
    end
  end
end
