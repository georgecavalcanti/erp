module Agent
  module Tools
    # Histórico de relacionamento (doc 06): contatos, visitas, tarefas e
    # observações registradas com o cliente — evita recomendar contato repetido.
    class ConsultarInteracoes < BaseTool
      tool_name "consultar_interacoes"
      description "Atividades registradas com um cliente da carteira (contatos, visitas, tarefas, " \
                  "observações e resultados), da mais recente para a mais antiga."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (partner)" },
          limite: { type: "integer", minimum: 1, maximum: 30,
                    description: "Quantidade máxima (opcional; default 10)" }
        },
        required: [ "partner_id" ],
        additionalProperties: false
      })

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        limit = (params["limite"] || 10).clamp(1, 30)
        activities = Activity.where(partner: partner).recent_first.limit(limit)

        {
          cliente: partner.name,
          interacoes: activities.map { |a|
            { tipo: a.kind_label, canal: a.channel, quando: a.occurred_at.iso8601,
              notas: a.notes }.compact
          },
          aviso: activities.none? ? "Nenhuma interação registrada com este cliente." : nil
        }.compact
      end
    end
  end
end
