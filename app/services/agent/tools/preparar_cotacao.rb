module Agent
  module Tools
    # Guarda o RASCUNHO de cotação (doc 06): itens e quantidades validados contra o
    # catálogo — SEM preços (fonte não integrada; nunca estimar) e SEM tocar o ERP
    # (não fatura, não cria pedido). O vendedor conclui a cotação no Sankhya.
    class PrepararCotacao < BaseTool
      tool_name "preparar_cotacao"
      description "Salva um rascunho de cotação para um cliente da carteira: lista de produtos e " \
                  "quantidades (validados no catálogo), com estoque de referência. NÃO grava no ERP, " \
                  "NÃO fatura e NÃO inclui preços — o vendedor conclui no Sankhya."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (partner)" },
          itens: {
            type: "array", minItems: 1, maxItems: 20,
            items: {
              type: "object",
              properties: {
                codigo: { type: "integer", description: "Código do produto (CODPROD)" },
                quantidade: { type: "number", exclusiveMinimum: 0, description: "Quantidade" }
              },
              required: %w[codigo quantidade],
              additionalProperties: false
            },
            description: "Itens da cotação"
          }
        },
        required: %w[partner_id itens],
        additionalProperties: false
      })

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        itens = build_items(params["itens"])

        activity = Activity.create!(
          user: user, salesperson: @salesperson, partner: partner,
          kind: :note,
          notes: "[Rascunho de cotação — NÃO enviado ao ERP] #{itens.size} item(ns): " +
                 itens.map { |i| "#{i[:descricao]} × #{i[:quantidade]}" }.join("; "),
          occurred_at: Time.current,
          outcome: { "tipo" => "rascunho_cotacao", "itens" => itens.map(&:stringify_keys) }
        )

        { rascunho_salvo: true, atividade_id: activity.id, cliente: partner.name, itens: itens,
          aviso: "Rascunho local sem preços (tabela não integrada). Conclua a cotação no Sankhya." }
      end

      private

      # Valida cada item contra o catálogo; produto inexistente é erro corrigível
      # (o modelo pode buscar o código certo com consultar_estoque).
      def build_items(raw_items)
        raw_items.map do |item|
          product = Product.find_by(external_code: item["codigo"])
          raise Invalid, "Produto de código #{item["codigo"]} não encontrado no catálogo." unless product

          qty = item["quantidade"].to_f
          raise Invalid, "Quantidade inválida para #{product.description}." unless qty.positive?

          { codigo: product.external_code, descricao: product.description,
            quantidade: qty, estoque_snapshot: product.stock_level&.sellable&.to_f }
        end
      end
    end
  end
end
