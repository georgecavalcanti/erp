module Sankhya
  # Consultas em tempo real (doc 03 §4.4): um SELECT pontual, com FALLBACK para o
  # espelho local + carimbo de origem ("dado de {timestamp}"). Usado antes de
  # recomendações sensíveis (Sprint 7+) — no Cliente 360, o estoque vem do snapshot
  # (rápido, N produtos); aqui é o dado ao vivo de UM produto quando importa.
  #
  # Resiliência: qualquer falha do gateway cai no snapshot; sem snapshot, sinaliza
  # "unavailable" — a tela nunca quebra por causa da integração.
  class LiveQueries
    def initialize(client: Sankhya::Client.new)
      @client = client
    end

    # Estoque disponível para venda de um produto AGORA.
    # => { sellable:, source: "live"|"snapshot"|"unavailable", as_of: }
    def stock(product)
      row = @client.execute_query(stock_sql(product.external_code)).first
      row ? live_stock(row) : snapshot_stock(product)
    rescue Sankhya::Error
      snapshot_stock(product)
    end

    private

    def stock_sql(codprod)
      <<~SQL.squish
        SELECT ESTOQUE, RESERVADO, WMSBLOQUEADO FROM TGFEST
        WHERE CODEMP = 1 AND CODLOCAL = 10100 AND CODPROD = #{codprod.to_i}
      SQL
    end

    def live_stock(row)
      sellable = to_d(row["ESTOQUE"]) - to_d(row["RESERVADO"]) - to_d(row["WMSBLOQUEADO"])
      { sellable: [ sellable, 0 ].max.to_f, source: "live", as_of: Time.current.iso8601 }
    end

    def snapshot_stock(product)
      level = product.stock_level
      return { sellable: nil, source: "unavailable", as_of: nil } unless level

      { sellable: level.sellable.to_f, source: "snapshot", as_of: level.synced_at.iso8601 }
    end

    def to_d(value)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal(0)
    end
  end
end
