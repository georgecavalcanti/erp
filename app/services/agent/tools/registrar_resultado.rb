module Agent
  module Tools
    # Registra o RESULTADO comercial de uma recomendação (doc 06): cria a receita
    # influenciada + atividade de resultado e conclui a recomendação — mesma regra
    # do RecommendationsController#result (Sprint 7). Base local apenas.
    class RegistrarResultado < BaseTool
      tool_name "registrar_resultado"
      description "Vincula um resultado comercial a uma recomendação do plano do dia: valor influenciado, " \
                  "nota fiscal (opcional, NUNOTA) e observação. Conclui a recomendação e alimenta a " \
                  "receita influenciada."
      input_schema({
        type: "object",
        properties: {
          recommendation_id: { type: "integer", description: "ID da recomendação do plano do dia" },
          valor: { type: "number", exclusiveMinimum: 0, description: "Valor influenciado em R$" },
          nota_uid: { type: "integer", description: "NUNOTA da nota vinculada (opcional)" },
          notas: { type: "string", description: "Observação do resultado (opcional)" }
        },
        required: %w[recommendation_id valor],
        additionalProperties: false
      })

      def execute(params)
        rec = authorized_recommendation!(params["recommendation_id"])
        amount = params["valor"].to_f
        raise Invalid, "Informe um valor influenciado maior que zero." unless amount.positive?

        invoice = find_invoice!(rec, params["nota_uid"])

        # A checagem de duplicidade fica DENTRO da transação, sob lock de linha:
        # duas chamadas simultâneas não criam duas receitas influenciadas para o
        # mesmo card (revisão cruzada Sprint 8).
        Recommendation.transaction do
          rec.lock!
          if rec.status_done? && rec.influenced_revenues.exists?
            raise Invalid, "Resultado já registrado para esta recomendação."
          end

          rec.influenced_revenues.create!(invoice: invoice, amount: amount, linked_by: :manual)
          rec.update!(status: :done, feedback: :useful, acted_at: Time.current)
          Activity.create!(
            user: user, partner: rec.partner, salesperson: rec.salesperson,
            kind: :result, notes: params["notas"].presence || "Resultado registrado via copiloto",
            occurred_at: Time.current, recommendation: rec
          )
        end

        { registrado: true, recomendacao_id: rec.id, cliente: rec.partner&.name,
          valor_influenciado: money(amount), nota: invoice&.external_uid }.compact
      end

      private

      # Mesmo limite do controller (vendedor autorizado) + o limite da CONVERSA:
      # com vendedor de contexto, só recomendações DELE.
      def authorized_recommendation!(id)
        rec = Recommendation.find_by(id: id)
        raise Invalid, "Recomendação #{id} não encontrada." unless rec

        ids = access.authorized_salesperson_ids
        unless ids.nil? || ids.include?(rec.salesperson_id)
          raise Denied, "Recomendação fora do seu escopo."
        end
        if @salesperson && rec.salesperson_id != @salesperson.id
          raise Denied, "Recomendação de outro vendedor — fora do contexto desta conversa."
        end

        rec
      end

      # A nota tem de ser DO CLIENTE da recomendação (integridade + RBAC).
      def find_invoice!(rec, nota_uid)
        return nil if nota_uid.blank?

        Invoice.find_by(external_uid: nota_uid, partner_id: rec.partner_id) or
          raise Invalid, "Nota #{nota_uid} não encontrada para este cliente."
      end
    end
  end
end
