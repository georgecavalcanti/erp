module Sankhya
  # Sincroniza a CARTEIRA (pedidos de venda pendentes, a faturar) do TGFCAB para
  # o modelo PendingOrder. É um SNAPSHOT: substitui a carteira inteira a cada run
  # (pedido pendente vira nota ou é cancelado com o tempo).
  #
  # ESCOPO (decisão 2026-07-08): TOP 1001 (PEDIDO DE VENDA PRIVADO), PENDENTE='S',
  # STATUSNOTA='L' (Liberada), empresa 1 (Jatto), e DTNEG no MÊS CORRENTE — espelha
  # o Portal de Pedidos do Sankhya, que filtra o mês atual. Mês via SYSDATE (TZ-safe).
  #
  #   Sankhya::PendingOrderSync.new.call            # grava (snapshot)
  #   Sankhya::PendingOrderSync.new.call(dry_run: true)  # só lê
  class PendingOrderSync
    TOPS = [ 1001 ].freeze # PEDIDO DE VENDA PRIVADO
    COMPANIES = [ 1 ].freeze # CODEMP 1 = JATTO
    PAGE_SIZE = 1000

    def initialize(client: Sankhya::Client.new, page_size: PAGE_SIZE)
      @client = client
      @page_size = page_size
      @partners = {}
      @salespeople = {}
    end

    def call(dry_run: false)
      attrs_list = fetch_all.map { |row| build_attrs(row) }
      total = attrs_list.sum { |a| a[:total_value].to_f }.round(2)

      if dry_run
        return {
          rows: attrs_list.size,
          total: total,
          sample: attrs_list.first(5).map { |a| a.slice(:external_uid, :total_value, :partner_name, :salesperson_label, :delivery_type, :note_status) }
        }
      end

      # Snapshot: substitui a carteira anterior atomicamente.
      PendingOrder.transaction do
        PendingOrder.delete_all
        attrs_list.each { |a| PendingOrder.create!(a) }
      end

      { rows: attrs_list.size, total: total }
    end

    private

    def fetch_all
      rows = []
      after = 0
      loop do
        raw = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if raw.empty?

        rows.concat(raw.uniq { |r| r["NUNOTA"] })
        after = raw.map { |r| r["NUNOTA"].to_i }.max
        break if raw.size < @page_size
      end
      rows
    end

    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT CAB.NUNOTA, CAB.CODPARC, CAB.CODVEND,
               TO_CHAR(CAB.DTNEG,'YYYY-MM-DD') DTNEG, TO_CHAR(CAB.DTMOV,'YYYY-MM-DD') DTMOV,
               CAB.VLRNOTA, CAB.STATUSNOTA, CAB.CIF_FOB,
               PAR.NOMEPARC, VEN.APELIDO
        FROM TGFCAB CAB
        LEFT JOIN TGFPAR PAR ON PAR.CODPARC = CAB.CODPARC
        LEFT JOIN TGFVEN VEN ON VEN.CODVEND = CAB.CODVEND
        WHERE CAB.CODTIPOPER IN (#{TOPS.join(',')})
          AND CAB.CODEMP IN (#{COMPANIES.join(',')})
          AND CAB.PENDENTE = 'S'
          AND CAB.STATUSNOTA = 'L'
          AND CAB.DTNEG >= TRUNC(SYSDATE, 'MM')
          AND CAB.DTNEG < ADD_MONTHS(TRUNC(SYSDATE, 'MM'), 1)
          AND CAB.NUNOTA > #{after.to_i}
        ORDER BY CAB.NUNOTA
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def build_attrs(row)
      {
        external_uid: row["NUNOTA"],
        order_number: row["NUNOTA"],
        partner: fetch_partner(row["CODPARC"], row["NOMEPARC"]),
        partner_name: row["NOMEPARC"].presence&.to_s,
        salesperson: fetch_salesperson(row["CODVEND"], row["APELIDO"]),
        salesperson_label: row["APELIDO"].presence&.to_s,
        negotiation_date: parse_date(row["DTNEG"]),
        movement_date: parse_date(row["DTMOV"]),
        total_value: row["VLRNOTA"] || 0,
        commission: 0, # comissão fica pro módulo financeiro (centro de custo)
        operation_type_desc: "PEDIDO DE VENDA PRIVADO",
        note_status: row["STATUSNOTA"].presence&.to_s,
        delivery_type: row["CIF_FOB"].presence&.to_s, # CIF/FOB ~ entrega/retira (refinar label depois)
        pending: true,
        raw: row
      }
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
