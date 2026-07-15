module Sankhya
  # Sincroniza os ITENS das notas (TGFITE) para InvoiceItem e consolida a
  # margem na própria nota (Invoice#total_cost/margin_value/margin_percent).
  #
  # Escopo espelha o InvoiceSync: empresa 1, TOPs de venda (1101) e devolução
  # (1201/1202). `since` (DTNEG) faz backfill/janela; `changed_within_hours`
  # (DTALTER da NOTA) faz o incremental — recomputa a margem das notas mexidas.
  #
  # Paginação por KEYSET COMPOSTO (NUNOTA, SEQUENCIA): uma nota nunca é partida
  # entre páginas de forma inconsistente porque o cursor guarda o par exato.
  # Grava em lote (upsert_all) — aguenta o backfill de ~960 mil itens (Fase 0).
  #
  #   Sankhya::InvoiceItemSync.new(since: Date.new(2024, 12, 1)).call  # backfill
  #   Sankhya::InvoiceItemSync.new(changed_within_hours: 24).call      # incremental
  class InvoiceItemSync
    SALES_TOPS  = [ 1101 ].freeze
    RETURN_TOPS = [ 1201, 1202 ].freeze
    TOPS = (SALES_TOPS + RETURN_TOPS).freeze
    COMPANIES = [ 1 ].freeze
    PAGE_SIZE = 2000

    def initialize(client: Sankhya::Client.new, since: nil, changed_within_hours: nil, page_size: PAGE_SIZE)
      @client = client
      @since = since
      @changed_within_hours = changed_within_hours
      @page_size = page_size
    end

    def call(dry_run: false)
      seen = upserted = skipped_no_invoice = 0
      sample = []
      touched = Set.new
      after_nunota = 0
      after_seq = 0

      loop do
        rows = @client.execute_query(page_sql(after_nunota: after_nunota, after_seq: after_seq, limit: @page_size))
        break if rows.empty?

        seen += rows.size
        invoice_ids = resolve_invoice_ids(rows)
        product_ids = resolve_product_ids(rows)
        now = Time.current

        records = rows.filter_map do |row|
          invoice_id = invoice_ids[row["NUNOTA"].to_i]
          if invoice_id.nil?
            skipped_no_invoice += 1
            next # item de nota fora do nosso espelho (ex.: pedido, outra empresa)
          end
          attrs = build_attrs(row, invoice_id, product_ids[row["CODPROD"].to_i], now)
          touched << invoice_id
          sample << attrs.slice(:external_sequence, :net_value, :total_cost, :margin_value) if dry_run && sample.size < 5
          attrs
        end

        unless dry_run || records.empty?
          InvoiceItem.upsert_all(records, unique_by: %i[invoice_id external_sequence])
          upserted += records.size
        end

        last = rows.last
        after_nunota = last["NUNOTA"].to_i
        after_seq = last["SEQUENCIA"].to_i
        break if rows.size < @page_size
      end

      rollup(touched) unless dry_run
      { rows: seen, upserted: upserted, invoices_touched: touched.size, skipped_no_invoice: skipped_no_invoice, sample: sample }
    end

    private

    def page_sql(after_nunota:, after_seq:, limit:)
      conds = [ "CAB.CODEMP IN (#{COMPANIES.join(',')})", "CAB.CODTIPOPER IN (#{TOPS.join(',')})" ]
      conds << "CAB.DTNEG >= TO_DATE('#{@since.strftime('%Y-%m-%d')}','YYYY-MM-DD')" if @since
      conds << "CAB.DTALTER >= SYSDATE - #{@changed_within_hours.to_f}/24" if @changed_within_hours
      # Keyset composto: avança para (NUNOTA, SEQUENCIA) estritamente maior que o cursor.
      conds << "(ITE.NUNOTA > #{after_nunota.to_i} OR (ITE.NUNOTA = #{after_nunota.to_i} AND ITE.SEQUENCIA > #{after_seq.to_i}))"

      <<~SQL.squish
        SELECT ITE.NUNOTA, ITE.SEQUENCIA, ITE.CODPROD, ITE.QTDNEG, ITE.VLRUNIT,
               ITE.VLRTOT, ITE.VLRDESC, ITE.CUSTO
        FROM TGFITE ITE
        JOIN TGFCAB CAB ON CAB.NUNOTA = ITE.NUNOTA
        WHERE #{conds.join(' AND ')}
        ORDER BY ITE.NUNOTA, ITE.SEQUENCIA
        FETCH FIRST #{limit.to_i} ROWS ONLY
      SQL
    end

    # external_uid (NUNOTA) -> invoice_id local, em um único SELECT por página.
    def resolve_invoice_ids(rows)
      nunotas = rows.map { |r| r["NUNOTA"].to_i }.uniq
      Invoice.where(external_uid: nunotas).pluck(:external_uid, :id).to_h
    end

    def resolve_product_ids(rows)
      codprods = rows.map { |r| r["CODPROD"].to_i }.uniq
      Product.where(external_code: codprods).pluck(:external_code, :id).to_h
    end

    def build_attrs(row, invoice_id, product_id, now)
      qty = to_d(row["QTDNEG"])
      gross = to_d(row["VLRTOT"])
      discount = to_d(row["VLRDESC"])
      net = gross - discount
      unit_cost = row["CUSTO"].present? ? to_d(row["CUSTO"]) : nil
      total_cost = unit_cost && (qty * unit_cost).round(2)
      {
        invoice_id: invoice_id,
        product_id: product_id,
        external_sequence: row["SEQUENCIA"].to_i,
        quantity: qty,
        unit_price: row["VLRUNIT"],
        gross_value: gross,
        discount_value: discount,
        net_value: net,
        unit_cost: unit_cost,
        total_cost: total_cost,
        margin_value: total_cost && (net - total_cost),
        raw: row,
        created_at: now,
        updated_at: now
      }
    end

    # Consolida margem/custo na nota a partir dos itens persistidos. Um único
    # UPDATE ... FROM (agregado) por lote de notas — barato mesmo no backfill.
    # touched vazio (nenhuma nota casada) -> nada a fazer.
    def rollup(invoice_ids)
      return if invoice_ids.empty?

      invoice_ids.each_slice(1000) do |ids|
        # ids são inteiros do próprio banco, mas passa por sanitize_sql_array
        # (placeholder ?) para não deixar SQL cru com interpolação.
        sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, ids ])
          UPDATE invoices inv SET
            total_cost = s.total_cost,
            margin_value = s.margin_value,
            margin_percent = CASE WHEN s.net_value <> 0
                                  THEN ROUND(s.margin_value / s.net_value * 100, 4) END,
            items_synced_at = NOW()
          FROM (
            SELECT invoice_id,
                   SUM(net_value)   AS net_value,
                   SUM(total_cost)  AS total_cost,
                   SUM(margin_value) AS margin_value
            FROM invoice_items
            WHERE invoice_id IN (?)
            GROUP BY invoice_id
          ) s
          WHERE inv.id = s.invoice_id
        SQL
        ActiveRecord::Base.connection.execute(sql)
      end
    end

    def to_d(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal(0)
    end
  end
end
