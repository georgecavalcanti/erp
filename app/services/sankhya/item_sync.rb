module Sankhya
  # Base compartilhada para sincronizar ITENS (TGFITE) — de notas ou de pedidos.
  # A mecânica é idêntica; só mudam os TOPs, o modelo-alvo (InvoiceItem/OrderItem),
  # o pai (Invoice/Order) e as tabelas do rollup. As subclasses configuram isso
  # sobrescrevendo os métodos de `config`.
  #
  # Paginação por KEYSET COMPOSTO (NUNOTA, SEQUENCIA): o cursor guarda o par
  # exato, então uma nota/pedido nunca é partido de forma inconsistente entre
  # páginas. Grava em lote (upsert_all) e consolida margem/custo no pai via um
  # único UPDATE ... FROM por lote — aguenta o backfill de centenas de milhares
  # de itens (Fase 0).
  class ItemSync
    COMPANIES = [ 1 ].freeze
    PAGE_SIZE = 2000

    def initialize(client: Sankhya::Client.new, since: nil, changed_within_hours: nil, page_size: PAGE_SIZE)
      @client = client
      @since = since
      @changed_within_hours = changed_within_hours
      @page_size = page_size
    end

    def call(dry_run: false)
      seen = upserted = skipped_no_parent = 0
      sample = []
      touched = Set.new
      # Sequências vistas por pai NESTE run — base do prune de itens que sumiram
      # do ERP. A query traz TODOS os itens de um cabeçalho casado, então o
      # conjunto por pai fica completo (ver #prune_removed).
      seen_sequences = Hash.new { |h, k| h[k] = Set.new }
      after_nunota = 0
      after_seq = 0

      loop do
        rows = @client.execute_query(page_sql(after_nunota: after_nunota, after_seq: after_seq, limit: @page_size))
        break if rows.empty?

        seen += rows.size
        parent_ids = resolve_parent_ids(rows)
        product_ids = resolve_product_ids(rows)
        now = Time.current

        records = rows.filter_map do |row|
          parent_id = parent_ids[row["NUNOTA"].to_i]
          if parent_id.nil?
            skipped_no_parent += 1
            next # item cujo cabeçalho não está no nosso espelho
          end
          attrs = build_attrs(row, parent_id, product_ids[row["CODPROD"].to_i], now)
          touched << parent_id
          seen_sequences[parent_id] << attrs[:external_sequence]
          sample << attrs.slice(:external_sequence, :net_value, :total_cost, :margin_value) if dry_run && sample.size < 5
          attrs
        end

        unless dry_run || records.empty?
          # upsert_all pula as validações do model DE PROPÓSITO: o dado do ERP é
          # confiável e já normalizado em build_attrs, e o lote (até 2000 linhas)
          # não comporta instanciar/validar cada item. on_duplicate preserva o
          # created_at original — sem ele o re-sync "renasceria" a linha.
          item_class.upsert_all(records, unique_by: [ parent_fk, :external_sequence ],
                                         on_duplicate: on_duplicate_clause(records.first))
          upserted += records.size
        end

        last = rows.last
        after_nunota = last["NUNOTA"].to_i
        after_seq = last["SEQUENCIA"].to_i
        break if rows.size < @page_size
      end

      unless dry_run
        prune_removed(seen_sequences) # tira itens que sumiram do ERP ANTES de somar
        rollup(touched)
      end
      { rows: seen, upserted: upserted, parents_touched: touched.size, skipped_no_parent: skipped_no_parent, sample: sample }
    end

    private

    # --- Config: subclasses sobrescrevem ---
    def tops = raise(NotImplementedError)
    def item_class = raise(NotImplementedError)         # InvoiceItem / OrderItem
    def parent_class = raise(NotImplementedError)       # Invoice / Order
    def parent_fk = raise(NotImplementedError)          # :invoice_id / :order_id
    def parent_table = raise(NotImplementedError)       # "invoices" / "orders"
    def item_table = raise(NotImplementedError)         # "invoice_items" / "order_items"

    def page_sql(after_nunota:, after_seq:, limit:)
      conds = [ "CAB.CODEMP IN (#{COMPANIES.join(',')})", "CAB.CODTIPOPER IN (#{tops.join(',')})" ]
      conds << "CAB.DTNEG >= TO_DATE('#{@since.strftime('%Y-%m-%d')}','YYYY-MM-DD')" if @since
      conds << "CAB.DTALTER >= SYSDATE - #{@changed_within_hours.to_f}/24" if @changed_within_hours
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

    # NUNOTA -> id local do cabeçalho (Invoice/Order), um SELECT por página.
    def resolve_parent_ids(rows)
      nunotas = rows.map { |r| r["NUNOTA"].to_i }.uniq
      parent_class.where(external_uid: nunotas).pluck(:external_uid, :id).to_h
    end

    def resolve_product_ids(rows)
      codprods = rows.map { |r| r["CODPROD"].to_i }.uniq
      Product.where(external_code: codprods).pluck(:external_code, :id).to_h
    end

    def build_attrs(row, parent_id, product_id, now)
      qty = to_d(row["QTDNEG"])
      gross = to_d(row["VLRTOT"])
      discount = to_d(row["VLRDESC"])
      net = gross - discount
      unit_cost = row["CUSTO"].present? ? to_d(row["CUSTO"]) : nil
      total_cost = unit_cost && (qty * unit_cost).round(2)
      {
        parent_fk => parent_id,
        :product_id => product_id,
        :external_sequence => row["SEQUENCIA"].to_i,
        :quantity => qty,
        :unit_price => row["VLRUNIT"],
        :gross_value => gross,
        :discount_value => discount,
        :net_value => net,
        :unit_cost => unit_cost,
        :total_cost => total_cost,
        :margin_value => total_cost && (net - total_cost),
        :raw => row,
        :created_at => now,
        :updated_at => now
      }
    end

    # ON CONFLICT DO UPDATE de todas as colunas do payload MENOS a chave natural
    # e created_at: o re-sync atualiza valores e updated_at, mas mantém a data de
    # criação original da linha.
    def on_duplicate_clause(sample_record)
      conn = item_class.connection
      cols = sample_record.keys - [ parent_fk, :external_sequence, :created_at ]
      Arel.sql(cols.map { |c| "#{conn.quote_column_name(c)} = excluded.#{conn.quote_column_name(c)}" }.join(", "))
    end

    # Remove itens que existiam localmente mas não voltaram do ERP neste run —
    # ex.: item retirado de um pedido ainda editável (nota liberada é imutável;
    # o risco real é em pedidos). Só varre os pais tocados e, como a query traz
    # todos os itens de cada cabeçalho casado, o que não foi visto foi apagado.
    def prune_removed(seen_sequences)
      seen_sequences.each do |parent_id, sequences|
        item_class.where(parent_fk => parent_id)
                  .where.not(external_sequence: sequences.to_a)
                  .delete_all
      end
    end

    # Consolida margem/custo no pai a partir dos itens persistidos.
    # parent_table/item_table/parent_fk vêm de constantes internas (não de input);
    # os ids passam por sanitize_sql_array (placeholder ?).
    #
    # margin_percent: receita líquida quase-zero (bonificação, 100% de desconto)
    # torna o percentual sem sentido analítico E estouraria numeric(7,4) — ex.:
    # net=0,50, custo=50 -> -9900% -> grava NULL. Fora disso, clampa a ±999,9999
    # para caber na coluna mesmo em anomalias (net baixo com custo alto).
    # (Sem comentários SQL inline: o heredoc é .squish -> uma linha; um `--`
    # comentaria o resto da query.)
    def rollup(parent_ids)
      return if parent_ids.empty?

      fk = parent_fk
      parent_ids.each_slice(1000) do |ids|
        sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, ids ])
          UPDATE #{parent_table} p SET
            total_cost = s.total_cost,
            margin_value = s.margin_value,
            margin_percent = CASE
              WHEN ABS(s.net_value) < 1 THEN NULL
              ELSE GREATEST(-999.9999, LEAST(999.9999, ROUND(s.margin_value / s.net_value * 100, 4)))
            END,
            items_synced_at = NOW()
          FROM (
            SELECT #{fk} AS pid,
                   SUM(net_value)    AS net_value,
                   SUM(total_cost)   AS total_cost,
                   SUM(margin_value) AS margin_value
            FROM #{item_table}
            WHERE #{fk} IN (?)
            GROUP BY #{fk}
          ) s
          WHERE p.id = s.pid
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
