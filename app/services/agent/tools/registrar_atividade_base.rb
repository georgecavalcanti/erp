module Agent
  module Tools
    # Base das ações de registro (doc 06, grupo Ação preparada): escrevem SOMENTE
    # na base local (activities) — nunca no ERP. O autor é sempre o usuário
    # autenticado; o cliente passa pelo mesmo limite de carteira das consultas.
    class RegistrarAtividadeBase < BaseTool
      def self.activity_kind(value = nil)
        @activity_kind = value if value
        @activity_kind
      end

      CHANNELS = %w[ligacao whatsapp visita email interno].freeze

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        raise Invalid, "Informe 'notas' descrevendo a interação." if params["notas"].blank?

        activity = Activity.create!(
          user: user, salesperson: @salesperson, partner: partner,
          kind: self.class.activity_kind,
          channel: params["canal"].presence,
          notes: params["notas"],
          occurred_at: parse_when(params["quando"])
        )

        { registrado: true, atividade_id: activity.id, cliente: partner.name,
          tipo: activity.kind_label, quando: activity.occurred_at.iso8601 }
      end

      protected

      def parse_when(value)
        return Time.current if value.blank?

        Time.zone.parse(value) || Time.current
      rescue ArgumentError
        raise Invalid, "Data/hora inválida em 'quando' — use formato ISO (YYYY-MM-DD ou YYYY-MM-DDTHH:MM)."
      end

      def self.base_schema(extra_properties = {}, required: %w[partner_id notas])
        {
          type: "object",
          properties: {
            partner_id: { type: "integer", description: "ID interno do cliente (partner)" },
            notas: { type: "string", minLength: 3, description: "Descrição objetiva da interação" },
            canal: { type: "string", enum: CHANNELS, description: "Canal utilizado (opcional)" },
            quando: { type: "string", description: "Quando ocorreu, ISO 8601 (opcional; default agora)" }
          }.merge(extra_properties),
          required: required,
          additionalProperties: false
        }
      end
    end
  end
end
