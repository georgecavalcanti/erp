module Agent
  module Tools
    # Guarda o RASCUNHO de mensagem redigido pelo agente (doc 06). NÃO ENVIA nada:
    # o texto fica como atividade-rascunho na base local e o vendedor copia/revisa
    # e envia pelo canal dele. Regra de segurança: comunicação externa só sai por
    # ação humana explícita.
    class PrepararMensagem < BaseTool
      tool_name "preparar_mensagem"
      description "Salva um rascunho de mensagem (WhatsApp/e-mail) para um cliente da carteira. " \
                  "NADA é enviado — o vendedor revisa, copia e envia por conta própria. " \
                  "Redija o texto completo em 'texto'."
      input_schema({
        type: "object",
        properties: {
          partner_id: { type: "integer", description: "ID interno do cliente (partner)" },
          canal: { type: "string", enum: %w[whatsapp email], description: "Canal pretendido" },
          texto: { type: "string", minLength: 10, description: "Texto completo do rascunho da mensagem" }
        },
        required: %w[partner_id canal texto],
        additionalProperties: false
      })

      def execute(params)
        partner = authorized_partner!(params["partner_id"])
        raise Invalid, "Rascunho vazio — redija o texto da mensagem." if params["texto"].to_s.strip.size < 10

        activity = Activity.create!(
          user: user, salesperson: @salesperson, partner: partner,
          kind: :note, channel: params["canal"],
          notes: "[Rascunho de mensagem — NÃO enviado] #{params["texto"]}",
          occurred_at: Time.current,
          outcome: { "tipo" => "rascunho_mensagem", "canal" => params["canal"] }
        )

        { rascunho_salvo: true, atividade_id: activity.id, cliente: partner.name,
          canal: params["canal"],
          aviso: "Rascunho salvo na base local. O envio é decisão do vendedor — nada foi enviado." }
      end
    end
  end
end
