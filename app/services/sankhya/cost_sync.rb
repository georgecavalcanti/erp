module Sankhya
  # Atualiza o CUSTO ATUAL de cada produto (Product#current_cost) a partir do
  # TGFCUS — custo gerencial vigente (CUSGER), o mais recente por produto na
  # empresa 1. Roda 1x/dia (custos mudam devagar; Fase 0: ~10 mil linhas,
  # atualizadas diariamente).
  #
  # NÃO confundir com o custo da margem histórica: a margem de uma venda usa
  # TGFITE.CUSTO (congelado na nota, gravado pelo InvoiceItemSync). current_cost
  # serve para simulações e margem de itens NOVOS (cotações, cross-sell).
  #
  #   Sankhya::CostSync.new.call
  class CostSync
    COMPANIES = [ 1 ].freeze
    PAGE_SIZE = 2000

    def initialize(client: Sankhya::Client.new, page_size: PAGE_SIZE)
      @client = client
      @page_size = page_size
    end

    def call(dry_run: false)
      updated = missing = seen = 0
      sample = []
      after = 0

      loop do
        rows = @client.execute_query(page_sql(after: after, limit: @page_size))
        break if rows.empty?

        rows.each do |row|
          seen += 1
          if dry_run
            sample << row.slice("CODPROD", "CUSGER", "DTATUAL") if sample.size < 5
            next
          end
          # update_all pontual: não instancia o produto e não mexe em updated_at
          # à toa. Produto ausente (custo sem cadastro correspondente) é contado.
          n = Product.where(external_code: row["CODPROD"]).update_all(current_cost: row["CUSGER"])
          n.zero? ? missing += 1 : updated += 1
        end

        after = rows.map { |r| r["CODPROD"].to_i }.max
        break if rows.size < @page_size
      end

      { rows: seen, updated: updated, missing: missing, sample: sample }
    end

    private

    # Um custo por produto: o de DTATUAL mais recente. Duas linhas empatadas na
    # mesma DTATUAL (mesmo dia) tornariam o custo NÃO-determinístico com a antiga
    # subconsulta MAX (ambas voltavam; a última do loop vencia à toa). ROW_NUMBER
    # com desempate por DTATUAL DESC, CUSGER DESC escolhe UMA linha por produto de
    # forma estável — e ainda garante CODPROD único, o que mantém a paginação
    # keyset limpa. CODLOCAL=0 = custo gerencial da empresa (não por depósito).
    def page_sql(after:, limit:)
      <<~SQL.squish
        SELECT CODPROD, CUSGER, DTATUAL FROM (
          SELECT CUS.CODPROD, CUS.CUSGER, TO_CHAR(CUS.DTATUAL,'YYYY-MM-DD') DTATUAL,
                 ROW_NUMBER() OVER (
                   PARTITION BY CUS.CODPROD ORDER BY CUS.DTATUAL DESC, CUS.CUSGER DESC
                 ) RN
          FROM TGFCUS CUS
          WHERE CUS.CODEMP IN (#{COMPANIES.join(',')})
            AND CUS.CODLOCAL = 0
            AND CUS.CODPROD > #{after.to_i}
        ) WHERE RN = 1
        ORDER BY CODPROD
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end
  end
end
