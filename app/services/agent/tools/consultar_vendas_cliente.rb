module Agent
  module Tools
    # Histórico de vendas do cliente (doc 06): evolução mensal líquida (devolução
    # negativa) e produtos mais comprados, com período parametrizável.
    class ConsultarVendasCliente < BaseTool
      tool_name "consultar_vendas_cliente"
      description "Histórico de vendas de um cliente da carteira: evolução mensal de receita/margem " \
                  "e os produtos mais comprados no período. 'meses' controla a janela (default 6, máx 24)."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (partner)" },
          meses: { type: "integer", minimum: 1, maximum: 24,
                   description: "Janela em meses (opcional; default 6)" }
        },
        required: [ "partner_id" ],
        additionalProperties: false
      })

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        months = int_param(params["meses"], default: 6, range: 1..24)
        report = Customer360Report.new(partner)

        {
          cliente: partner.name,
          janela_meses: months,
          evolucao_mensal: report.monthly_evolution(months: months),
          top_produtos: report.top_products(limit: 10)
        }
      end
    end
  end
end
