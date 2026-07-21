module Agent
  module Tools
    # Oportunidades de cross-sell do cliente (doc 06, grupo Análise): categorias
    # que pares do mesmo porte/UF compram e este cliente não (Engines::CrossSell,
    # potencial pela mediana dos pares — determinístico).
    class IdentificarCrossSell < BaseTool
      tool_name "identificar_cross_sell"
      description "Categorias que clientes semelhantes (mesmo porte e UF) compram e este cliente " \
                  "ainda não compra, com potencial estimado — base para oferta de mix novo."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (partner)" }
        },
        required: [ "partner_id" ],
        additionalProperties: false
      })

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        opportunities = Engines::CrossSell.new(partner).call

        {
          cliente: partner.name,
          oportunidades: opportunities.map { |o|
            { categoria: o[:category_name], pares_comprando: o[:peers_buying],
              potencial: money(o[:potential_value]) }
          },
          aviso: opportunities.empty? ? "Sem base de comparação suficiente (pares do mesmo porte/UF) ou cliente já compra todas as categorias relevantes." : nil
        }.compact
      end
    end
  end
end
