module Agent
  module Tools
    # Potencial do cliente (doc 06, grupo Análise): COMBINA os sinais persistidos
    # dos motores — recompras abertas, cross-sell e perda por queda de consumo —
    # num potencial total com decomposição rastreável. O agente interpreta;
    # a matemática é dos motores.
    class CalcularPotencialCliente < BaseTool
      tool_name "calcular_potencial_cliente"
      description "Potencial de receita de um cliente da carteira, decomposto em: recompras em aberto, " \
                  "oportunidades de cross-sell e recuperação de queda de consumo."
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

        # Recompra em UM nível só: cliente > produto > categoria. Somar os três
        # contaria a mesma compra esperada 2–3× (o nível cliente já engloba os
        # itens — revisão cruzada Sprint 8).
        by_level = RepurchasePrediction.status_open.where(partner: partner)
                                       .group(:level).sum(:expected_value)
        repurchase = (by_level["customer"] || by_level["product"] || by_level["category"] || 0).to_f
        cross_sell = Engines::CrossSell.new(partner).call.sum { |o| o[:potential_value] }
        drop = Engines::ConsumptionDrop.new(partner).call
        recovery = drop[:trend] == :drop ? drop[:absolute_lost] : 0.0

        {
          cliente: partner.name,
          potencial_total: money(repurchase + cross_sell + recovery),
          decomposicao: {
            recompras_abertas: money(repurchase),
            cross_sell: money(cross_sell),
            recuperacao_queda: money(recovery)
          },
          tendencia_consumo: drop[:trend]
        }
      end
    end
  end
end
