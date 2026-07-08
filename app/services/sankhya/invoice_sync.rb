module Sankhya
  # Sincroniza NOTAS de venda + devolução (empresa Jatto) do TGFCAB
  # para o modelo Invoice, via executeQuery (Oracle) + InvoiceWriter (upsert por NUNOTA).
  #
  # Paginação keyset por NUNOTA + FETCH FIRST: processa em páginas de PAGE_SIZE
  # para backfill de qualquer tamanho sem estourar o burstLimit do executeQuery.
  #
  # ESCOPO (decisão de negócio 2026-07-08), empresa 1 (Jatto Distribuidora):
  #   Venda:     1101 (VENDA NF-E PRIVADO)
  #   Devolução: 1201, 1202 (DEVOLUÇÃO DE VENDA - NF própria / terceiros)
  # Exclui 1125, remessas, ajustes e a empresa 2 (Papel Leão).
  #
  #   Sankhya::InvoiceSync.new(since: Date.current - 7).call            # grava
  #   Sankhya::InvoiceSync.new(since: nil).call(dry_run: true)          # full, só lê
  class InvoiceSync
    SALES_TOPS  = [ 1101 ].freeze        # VENDA NF-E PRIVADO
    RETURN_TOPS = [ 1201, 1202 ].freeze  # DEVOLUÇÃO DE VENDA (NF própria / terceiros)
    COMPANIES   = [ 1 ].freeze           # CODEMP 1 = JATTO DISTRIBUIDORA (exclui 2 = Papel Leão)
    TOPS = (SALES_TOPS + RETURN_TOPS).freeze

    TOP_DESC = {
      1101 => "VENDA NF-E PRIVADO",
      1201 => "DEVOLUÇÃO DE VENDA - NF PRÓPRIA",
      1202 => "DEVOLUÇÃO DE VENDA - NF TERCEIROS"
    }.freeze

    PAGE_SIZE = 1000

    def initialize(client: Sankhya::Client.new, since: nil, changed_within_hours: nil, page_size: PAGE_SIZE)
      @client = client
      @since = since                               # filtra por DTNEG (backfill / janela histórica)
      @changed_within_hours = changed_within_hours # filtra por DTALTER nas últimas N horas (incremental)
      @page_size = page_size
    end

    # dry_run: true -> não grava; retorna amostra do que gravaria.
    def call(dry_run: false)
      writer = Sankhya::InvoiceWriter.new
      imported = updated = skipped = seen = 0
      sample = []
      after = 0

      loop do
        raw = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if raw.empty?

        # dedup por NUNOTA: LEFT JOINs versionados (ex.: TGFTPV) multiplicam linha;
        # o TGFCAB é 1 por NUNOTA. Paginação decide fim pelo total BRUTO da página.
        rows = raw.uniq { |r| r["NUNOTA"] }
        rows.each do |row|
          attrs = map(row)
          if dry_run
            sample << attrs if sample.size < 5
            next
          end
          begin
            writer.upsert(attrs) ? imported += 1 : updated += 1
          rescue => e
            # Uma linha ruim não aborta o backfill inteiro.
            skipped += 1
            Rails.logger.warn("[Sankhya::InvoiceSync] NUNOTA #{attrs[:external_uid]} pulada: #{e.message}")
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
      # SYSDATE = relógio do próprio banco → evita descasamento de fuso (app UTC x ERP local).
      conds << "CAB.DTALTER >= SYSDATE - #{@changed_within_hours.to_f}/24" if @changed_within_hours

      <<~SQL.squish
        SELECT CAB.NUNOTA, CAB.NUMNOTA, CAB.CODPARC, CAB.CODVEND, CAB.CODEMP,
               TO_CHAR(CAB.DTNEG, 'YYYY-MM-DD') DTNEG,
               CAB.VLRNOTA, CAB.CODTIPOPER, CAB.STATUSNOTA,
               PAR.NOMEPARC, VEN.APELIDO, EMP.NOMEFANTASIA, TPV.DESCRTIPVENDA
        FROM TGFCAB CAB
        LEFT JOIN TGFPAR PAR ON PAR.CODPARC = CAB.CODPARC
        LEFT JOIN TGFVEN VEN ON VEN.CODVEND = CAB.CODVEND
        LEFT JOIN TSIEMP EMP ON EMP.CODEMP = CAB.CODEMP
        LEFT JOIN TGFTPV TPV ON TPV.CODTIPVENDA = CAB.CODTIPVENDA
        WHERE #{conds.join(' AND ')}
        ORDER BY CAB.NUNOTA
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    def map(row)
      code = row["CODTIPOPER"].to_i
      {
        external_uid: row["NUNOTA"],
        invoice_number: row["NUMNOTA"],
        company_code: row["CODEMP"], company_name: row["NOMEFANTASIA"],
        partner_code: row["CODPARC"], partner_name: row["NOMEPARC"],
        salesperson_code: row["CODVEND"], salesperson_nickname: row["APELIDO"],
        negotiation_date: parse_date(row["DTNEG"]),
        total_value: row["VLRNOTA"],
        commission: 0, # comissão fica pro módulo financeiro (centro de custo), depois
        payment_terms_raw: row["DESCRTIPVENDA"],
        operation_type_desc: TOP_DESC[code],
        confirmed: row["STATUSNOTA"].to_s == "L",
        raw: row
      }
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
