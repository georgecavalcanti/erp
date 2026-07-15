# Client falso para testar syncs sem bater no gateway: recebe as linhas que o
# ERP "devolveria" e emula a paginação keyset dos syncs, interpretando o SQL
# gerado (o "> N", o keyset composto e o "FETCH FIRST L ROWS ONLY").
class FakeSankhyaClient
  attr_reader :queries

  # rows:       Array<Hash> (linhas completas, como o gateway devolve)
  # key:        coluna do keyset simples ("CODPROD"...) — nil p/ query sem paginação
  # composite:  [colA, colB] p/ keyset composto (InvoiceItemSync: NUNOTA, SEQUENCIA)
  def initialize(rows:, key: nil, composite: nil)
    @rows = rows
    @key = key
    @composite = composite
    @queries = []
  end

  def execute_query(sql, allow_burst: false)
    @queries << sql
    result = @rows
    result = apply_composite(sql, result) if @composite
    result = apply_single(sql, result) if @key
    if (limit = sql[/FETCH FIRST (\d+) ROWS ONLY/, 1])
      result = result.first(limit.to_i)
    end
    result
  end

  private

  def apply_single(sql, rows)
    return rows unless (after = sql[/#{@key} > (-?\d+)/, 1])

    rows.select { |r| r[@key].to_i > after.to_i }.sort_by { |r| r[@key].to_i }
  end

  # Casa "(<A> > n OR (<A> = n AND <B> > m))" — cursor (n, m) do keyset composto.
  def apply_composite(sql, rows)
    a, b = @composite
    m = sql.match(/#{a} > (-?\d+) OR .*?#{a} = -?\d+ AND \w*\.?#{b} > (-?\d+)/)
    return rows unless m

    after_a = m[1].to_i
    after_b = m[2].to_i
    rows.select { |r| r[a].to_i > after_a || (r[a].to_i == after_a && r[b].to_i > after_b) }
        .sort_by { |r| [ r[a].to_i, r[b].to_i ] }
  end
end
