module Agent
  module Tools
    # Pedidos pendentes (doc 06): de um cliente ou da carteira toda do vendedor.
    # Fonte: Order.portfolio (espelho persistente de pedidos, Sprint 2B).
    class ConsultarPedidosAbertos < BaseTool
      tool_name "consultar_pedidos_abertos"
      description "Pedidos pendentes (ainda não faturados). Com 'partner_id', só os do cliente; " \
                  "sem, todos os da carteira do vendedor."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (opcional)" }
        },
        additionalProperties: false
      })

      LIMIT = 30

      def execute(params)
        orders = scoped_orders(params["partner_id"]).order(negotiation_date: :desc)
        total = orders.sum(:total_value)

        {
          quantidade: orders.count,
          valor_total: money(total),
          pedidos: orders.limit(LIMIT).includes(:partner).map { |o|
            { numero: o.external_uid, cliente: o.partner&.name, data: o.negotiation_date,
              valor: money(o.total_value), situacao: o.note_status, tipo_entrega: o.delivery_type }.compact
          }
        }
      end

      private

      def scoped_orders(partner_id)
        if partner_id.present?
          Order.portfolio.where(partner: authorized_partner!(partner_id))
        else
          Order.portfolio.where(salesperson: salesperson!)
        end
      end
    end
  end
end
