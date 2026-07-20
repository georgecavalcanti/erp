module Agent
  module Tools
    # Cria uma TAREFA com prazo para o vendedor (activity kind=task) — doc 06.
    # O prazo vai em outcome.prazo (a agenda do vendedor lê de lá).
    class CriarTarefa < RegistrarAtividadeBase
      tool_name "criar_tarefa"
      description "Cria uma tarefa com prazo para o vendedor sobre um cliente da carteira " \
                  "(ex.: 'ligar na quinta para fechar o pedido'). Base local apenas."
      input_schema base_schema(
        { prazo: { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$",
                   description: "Data limite da tarefa (YYYY-MM-DD)" } },
        required: %w[partner_id notas prazo]
      )
      activity_kind :task

      def execute(params)
        due_on = parse_due(params["prazo"])
        partner = authorized_partner!(params["partner_id"])
        raise Invalid, "Informe 'notas' descrevendo a tarefa." if params["notas"].blank?

        activity = Activity.create!(
          user: user, salesperson: @salesperson, partner: partner,
          kind: :task, notes: params["notas"], occurred_at: Time.current,
          outcome: { "prazo" => due_on.iso8601 }
        )

        { registrado: true, atividade_id: activity.id, cliente: partner.name,
          tarefa: params["notas"], prazo: due_on }
      end

      private

      def parse_due(value)
        date = Date.iso8601(value.to_s)
        raise Invalid, "Prazo no passado — use uma data de hoje em diante." if date < Date.current

        date
      rescue Date::Error
        raise Invalid, "Prazo inválido — use o formato YYYY-MM-DD."
      end
    end
  end
end
