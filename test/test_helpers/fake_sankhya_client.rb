# Client falso para testar syncs sem bater no gateway: recebe as linhas que o
# ERP "devolveria" e emula a paginação keyset dos syncs, interpretando o
# "<KEY> > N" e o "FETCH FIRST L ROWS ONLY" do SQL gerado.
class FakeSankhyaClient
  attr_reader :queries

  # rows: Array<Hash> (linhas completas, como o gateway devolve)
  # key:  coluna do keyset ("CODPROD", "CODPARC"...) — nil p/ queries sem paginação
  def initialize(rows:, key: nil)
    @rows = rows
    @key = key
    @queries = []
  end

  def execute_query(sql, allow_burst: false)
    @queries << sql
    result = @rows
    if @key && (after = sql[/#{@key} > (-?\d+)/, 1])
      result = result.select { |r| r[@key].to_i > after.to_i }
                     .sort_by { |r| r[@key].to_i }
    end
    if (limit = sql[/FETCH FIRST (\d+) ROWS ONLY/, 1])
      result = result.first(limit.to_i)
    end
    result
  end
end
