module Agent
  module Tools
    # Situação de crédito do cliente (doc 06). Fase 0 definiu: crédito = bloqueio
    # + inadimplência (LIMCRED não integrado). Fonte: espelho local (partners +
    # overdue_titles) — a resposta carrega a origem e o carimbo do dado.
    class ConsultarCredito < BaseTool
      tool_name "consultar_credito"
      description "Situação de crédito de um cliente da carteira: bloqueio comercial (e motivo), " \
                  "títulos vencidos em aberto e protestados. Use antes de propor venda a prazo. " \
                  "Limite de crédito (LIMCRED) não está integrado — não estime limite."
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
        titles = OverdueTitle.where(partner_id: partner.id)
        open = titles.category_open
        worst_delay = open.maximum(:days_overdue)

        {
          cliente: partner.name,
          bloqueado: partner.blocked,
          motivo_bloqueio: partner.block_reason,
          titulos_vencidos: {
            quantidade: open.count,
            valor_aberto: money(open.sum(:amount)),
            valor_protestado: money(titles.category_protested.sum(:amount)),
            maior_atraso_dias: worst_delay
          },
          origem: "espelho",
          dado_de: partner.updated_at.iso8601,
          aviso: "Limite de crédito (LIMCRED) não integrado — avalie por bloqueio e inadimplência."
        }.compact
      end
    end
  end
end
