module Sankhya
  # Sincroniza a INADIMPLÊNCIA (títulos a receber em aberto e vencidos) do TGFFIN
  # para o modelo OverdueTitle, e reconstrói o resumo por vendedor (Delinquency).
  # É um SNAPSHOT: substitui todo o conjunto a cada run.
  #
  # ESCOPO (regras do George, 2026-07-08), empresa 1 (Jatto):
  #   * a receber (RECDESP=1), lançamento real (PROVISAO='N'), SEM baixa (DHBAIXA IS NULL);
  #   * vencimento entre 2025-01-01 e ontem (DTVENC >= 2025 e < hoje = D-1);
  #   * tipo de título BOLETO ou PIX (TGFTIT.DESCRTIPTIT);
  #   * exclui vendedor 0 (<SEM VENDEDOR>) e 27 (EMPRESA), via CODVEND da nota;
  #   * NÃO conta se o HISTORICO contém "Pendente" (case-insensitive).
  #   * Protestado = HISTORICO contém "protest" (case-insensitive).
  class OverdueTitleSync
    include DelinquencyAggregation

    COMPANIES     = [ 1 ].freeze     # CODEMP 1 = JATTO
    EXCLUDED_VEND = [ 0, 27 ].freeze # <SEM VENDEDOR>, EMPRESA
    PAGE_SIZE = 2000

    def initialize(client: Sankhya::Client.new, batch: nil, page_size: PAGE_SIZE)
      @client = client
      @batch = batch # usado por DelinquencyAggregation#derive_delinquency_summary
      @page_size = page_size
      @partners = {}
      @salespeople = {}
    end

    def call(dry_run: false)
      attrs_list = fetch_all.map { |row| build_attrs(row) }
      total = attrs_list.sum { |a| a[:amount].to_f }.round(2)
      protested = attrs_list.count { |a| a[:category] == :protested }

      if dry_run
        return {
          rows: attrs_list.size, total: total, protested: protested,
          sample: attrs_list.first(5).map { |a| a.slice(:external_uid, :amount, :due_date, :days_overdue, :category, :title_type, :partner_name, :salesperson_label) }
        }
      end

      OverdueTitle.transaction do
        OverdueTitle.delete_all
        attrs_list.each { |a| OverdueTitle.create!(a) }
      end
      derive_delinquency_summary # reconstrói o resumo Delinquency por vendedor

      { rows: attrs_list.size, total: total, protested: protested }
    end

    private

    def fetch_all
      rows = []
      after = 0
      loop do
        raw = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if raw.empty?

        rows.concat(raw.uniq { |r| r["NUFIN"] })
        after = raw.map { |r| r["NUFIN"].to_i }.max
        break if raw.size < @page_size
      end
      rows
    end

    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT FIN.NUFIN, FIN.NUNOTA, FIN.CODPARC,
               TO_CHAR(FIN.DTVENC,'YYYY-MM-DD') DTVENC,
               ROUND(FIN.VLRDESDOB - NVL(FIN.VLRBAIXA,0), 2) SALDO,
               TRUNC(SYSDATE) - TRUNC(FIN.DTVENC) DIAS,
               FIN.HISTORICO, CAB.NUMNOTA, CAB.CODVEND,
               PAR.NOMEPARC, VEN.APELIDO, TIT.DESCRTIPTIT
        FROM TGFFIN FIN
        JOIN TGFCAB CAB ON CAB.NUNOTA = FIN.NUNOTA
        JOIN TGFTIT TIT ON TIT.CODTIPTIT = FIN.CODTIPTIT
        LEFT JOIN TGFPAR PAR ON PAR.CODPARC = FIN.CODPARC
        LEFT JOIN TGFVEN VEN ON VEN.CODVEND = CAB.CODVEND
        WHERE FIN.RECDESP = 1
          AND FIN.PROVISAO = 'N'
          AND FIN.DHBAIXA IS NULL
          AND FIN.DTVENC >= TO_DATE('2025-01-01','YYYY-MM-DD')
          AND FIN.DTVENC < TRUNC(SYSDATE)
          AND FIN.CODEMP = #{COMPANIES.first}
          AND CAB.CODVEND NOT IN (#{EXCLUDED_VEND.join(',')})
          AND (FIN.HISTORICO IS NULL OR UPPER(FIN.HISTORICO) NOT LIKE '%PENDENTE%')
          AND (UPPER(TIT.DESCRTIPTIT) LIKE '%BOLETO%' OR UPPER(TIT.DESCRTIPTIT) LIKE '%PIX%')
          AND FIN.NUFIN > #{after.to_i}
        ORDER BY FIN.NUFIN
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def build_attrs(row)
      historico = row["HISTORICO"].to_s
      protested = historico.upcase.include?("PROTEST")
      due = parse_date(row["DTVENC"])
      {
        external_uid: row["NUNOTA"],
        invoice_number: row["NUMNOTA"],
        partner: fetch_partner(row["CODPARC"], row["NOMEPARC"]),
        partner_name: row["NOMEPARC"].presence&.to_s,
        salesperson: fetch_salesperson(row["CODVEND"], row["APELIDO"]),
        salesperson_label: row["APELIDO"].presence&.to_s || "—",
        due_date: due,
        days_overdue: row["DIAS"]&.to_i,
        amount: row["SALDO"] || 0,
        category: protested ? :protested : :open,
        protest_year: (protested && due ? due.year : nil),
        title_type: row["DESCRTIPTIT"].presence&.to_s,
        observation: historico.presence,
        import_batch: @batch
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
