module Sankhya
  # Sincroniza o HISTÓRICO de pedidos de venda (TOP 1001) para Order, upsert por
  # NUNOTA — preserva histórico e status (diferente do PendingOrderSync, que é
  # snapshot só da carteira do mês corrente para a tela Carteira).
  #
  # Status derivado do par (STATUSNOTA, PENDENTE) — mapa da Fase 0:
  #   PENDENTE='S' & STATUSNOTA='L' -> pending   (a faturar)
  #   PENDENTE='S' & STATUSNOTA='A' -> awaiting  (aguardando liberação)
  #   PENDENTE='N'                  -> billed    (faturado)
  #
  # `since` (DTNEG) faz backfill/janela; `changed_within_hours` (DTALTER) faz o
  # incremental — reflete pedidos que mudaram de status (ex.: viraram nota).
  #
  #   Sankhya::OrderSync.new(since: Date.new(2024, 12, 1)).call  # backfill
  #   Sankhya::OrderSync.new(changed_within_hours: 24).call      # incremental
  class OrderSync
    TOPS = [ 1001 ].freeze
    COMPANIES = [ 1 ].freeze
    PAGE_SIZE = 1000

    def initialize(client: Sankhya::Client.new, since: nil, changed_within_hours: nil, page_size: PAGE_SIZE)
      @client = client
      @since = since
      @changed_within_hours = changed_within_hours
      @page_size = page_size
      @companies = {}
      @partners = {}
      @salespeople = {}
    end

    def call(dry_run: false)
      imported = updated = skipped = seen = 0
      sample = []
      after = 0

      loop do
        raw = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if raw.empty?

        rows = raw.uniq { |r| r["NUNOTA"] }
        rows.each do |row|
          attrs = build_attrs(row)
          if dry_run
            sample << attrs.slice(:external_uid, :status, :total_value, :note_status, :pending) if sample.size < 5
            next
          end
          begin
            upsert(attrs) ? imported += 1 : updated += 1
          rescue => e
            skipped += 1
            Rails.logger.warn("[Sankhya::OrderSync] NUNOTA #{attrs[:external_uid]} pulado: #{e.message}")
          end
        end

        seen += rows.size
        after = raw.map { |r| r["NUNOTA"].to_i }.max
        break if raw.size < @page_size
      end

      { rows: seen, imported: imported, updated: updated, skipped: skipped, sample: sample }
    end

    private

    def page_sql(after:, limit:)
      conds = [ "CAB.CODTIPOPER IN (#{TOPS.join(',')})", "CAB.CODEMP IN (#{COMPANIES.join(',')})", "CAB.NUNOTA > #{after.to_i}" ]
      conds << "CAB.DTNEG >= TO_DATE('#{@since.strftime('%Y-%m-%d')}','YYYY-MM-DD')" if @since
      conds << "CAB.DTALTER >= SYSDATE - #{@changed_within_hours.to_f}/24" if @changed_within_hours

      <<~SQL.squish
        SELECT CAB.NUNOTA, CAB.CODPARC, CAB.CODVEND, CAB.CODEMP,
               TO_CHAR(CAB.DTNEG,'YYYY-MM-DD') DTNEG, TO_CHAR(CAB.DTMOV,'YYYY-MM-DD') DTMOV,
               CAB.VLRNOTA, CAB.STATUSNOTA, CAB.PENDENTE, CAB.CIF_FOB,
               PAR.NOMEPARC, VEN.APELIDO, EMP.NOMEFANTASIA
        FROM TGFCAB CAB
        LEFT JOIN TGFPAR PAR ON PAR.CODPARC = CAB.CODPARC
        LEFT JOIN TGFVEN VEN ON VEN.CODVEND = CAB.CODVEND
        LEFT JOIN TSIEMP EMP ON EMP.CODEMP = CAB.CODEMP
        WHERE #{conds.join(' AND ')}
        ORDER BY CAB.NUNOTA
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def build_attrs(row)
      pending = row["PENDENTE"].to_s == "S"
      {
        external_uid: row["NUNOTA"],
        order_number: row["NUNOTA"],
        company: fetch_company(row["CODEMP"], row["NOMEFANTASIA"]),
        partner: fetch_partner(row["CODPARC"], row["NOMEPARC"]),
        partner_name: row["NOMEPARC"].presence&.to_s,
        salesperson: fetch_salesperson(row["CODVEND"], row["APELIDO"]),
        salesperson_label: row["APELIDO"].presence&.to_s,
        negotiation_date: parse_date(row["DTNEG"]),
        movement_date: parse_date(row["DTMOV"]),
        total_value: row["VLRNOTA"] || 0,
        status: derive_status(row["STATUSNOTA"], pending),
        note_status: row["STATUSNOTA"].presence&.to_s,
        pending: pending,
        delivery_type: row["CIF_FOB"].presence&.to_s,
        raw: row
      }
    end

    def derive_status(status_nota, pending)
      return :billed unless pending
      return :awaiting if status_nota.to_s == "A"

      :pending
    end

    def upsert(attrs)
      order = Order.find_or_initialize_by(external_uid: attrs[:external_uid])
      was_new = order.new_record?
      order.assign_attributes(attrs)
      order.save!
      was_new
    end

    def fetch_company(code, name)
      return nil if code.nil?

      @companies[code] ||= Company.upsert_from(external_code: code, name: name.to_s)
    end

    def fetch_partner(code, name)
      return nil if code.nil?

      @partners[code] ||= Partner.upsert_from(external_code: code, name: name.to_s)
    end

    def fetch_salesperson(code, nickname)
      return nil if code.nil?

      @salespeople[code] ||= Salesperson.upsert_from(external_code: code, nickname: nickname.to_s)
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
