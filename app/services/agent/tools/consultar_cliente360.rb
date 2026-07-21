module Agent
  module Tools
    # Consolidado do cliente (doc 06): receita, margem, ticket, frequência,
    # situação financeira e cadastro. Reusa o Customer360Report (espelho local,
    # <2s, sem IA) — mesma fonte da tela Cliente 360.
    class ConsultarCliente360 < BaseTool
      tool_name "consultar_cliente_360"
      description "Consolidado de um cliente da carteira: cadastro, receita total/12m, margem, " \
                  "ticket médio, frequência de compra, última compra e situação financeira (bloqueio/inadimplência)."
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
        report = Customer360Report.new(partner)

        {
          cadastro: report.identification,
          resumo: report.summary,
          financeiro: report.financial,
          mix_categorias: report.mix_by_category(limit: 5)
        }
      end
    end
  end
end
