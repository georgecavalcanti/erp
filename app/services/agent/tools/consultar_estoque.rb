module Agent
  module Tools
    # Disponibilidade de estoque (doc 06): TEMPO REAL via Sankhya::LiveQueries
    # quando a busca resolve em UM produto; snapshot do espelho quando há vários
    # candidatos. Toda resposta carrega a origem do dado ("live"/"snapshot") —
    # regra do doc 06: não informar estoque sem consulta válida.
    #
    # O catálogo de produtos é global (não é recortado por carteira) — o que é
    # sensível por carteira são clientes/vendas, não a disponibilidade de item.
    class ConsultarEstoque < BaseTool
      tool_name "consultar_estoque"
      description "Disponibilidade de estoque de produto(s). Busca por código ou termo da descrição. " \
                  "Um único produto encontrado → consulta em tempo real no ERP; vários → snapshot do espelho. " \
                  "Sempre informe ao vendedor a origem (live/snapshot) e o horário do dado."
      input_schema({
        type: "object",
        properties: {
          produto: { type: "string", minLength: 2,
                     description: "Código do produto (CODPROD) ou termo da descrição" }
        },
        required: [ "produto" ],
        additionalProperties: false
      })

      MAX_MATCHES = 5

      def execute(params)
        products = find_products(params["produto"].to_s.strip)
        if products.empty?
          return { produtos: [], aviso: "Nenhum produto encontrado para '#{params["produto"]}'. " \
                                        "Peça um código ou termo mais específico — não estime estoque." }
        end

        if products.size == 1
          product = products.first
          { produtos: [ entry(product, Sankhya::LiveQueries.new.stock(product)) ] }
        else
          { produtos: products.map { |p| entry(p, snapshot(p)) },
            aviso: "#{products.size} produtos casaram com o termo — estoque via snapshot. " \
                   "Refine para 1 produto para consulta em tempo real." }
        end
      end

      private

      def find_products(term)
        scope = Product.where(active: true)
        if term.match?(/\A\d+\z/)
          Array(scope.find_by(external_code: term.to_i))
        else
          scope.where("description ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
               .order(:description).limit(MAX_MATCHES).to_a
        end
      end

      def snapshot(product)
        level = product.stock_level
        return { sellable: nil, source: "unavailable", as_of: nil } unless level

        { sellable: level.sellable.to_f, source: "snapshot", as_of: level.synced_at.iso8601 }
      end

      def entry(product, stock)
        { codigo: product.external_code, descricao: product.description, unidade: product.unit,
          disponivel: stock[:sellable], origem: stock[:source], dado_de: stock[:as_of] }
      end
    end
  end
end
