module Agent
  module Tools
    # Clientes em risco na carteira (doc 06, grupo Análise). Classificação
    # determinística do Engines::Risk sobre a carteira do vendedor — o escopo é a
    # carteira injetada, nunca um parâmetro do modelo.
    class DetectarClientesEmRisco < BaseTool
      tool_name "detectar_clientes_em_risco"
      description "Classifica a carteira do vendedor e devolve os clientes em risco, inativos ou em " \
                  "atenção, com os sinais de cada um (inadimplência, recompra atrasada, queda, sem contato)."

      ALERT_STATUSES = %w[em_risco inativo em_atencao].freeze
      LIMIT = 20

      def execute(_params)
        sp = salesperson!
        ids = Wallet.active.where(salesperson: sp).distinct.pluck(:partner_id)
        return { clientes: [], aviso: "Carteira vazia — nenhum cliente vinculado." } if ids.empty?

        names = Partner.where(id: ids).pluck(:id, :name).to_h
        flagged = Engines::Risk.classify_many(ids)
                               .select { |_id, r| ALERT_STATUSES.include?(r[:status].to_s) }
                               .sort_by { |_id, r| ALERT_STATUSES.index(r[:status].to_s) }

        {
          carteira: ids.size,
          em_alerta: flagged.size,
          clientes: flagged.first(LIMIT).map { |id, r|
            { partner_id: id, cliente: names[id], status: r[:status], rotulo: r[:status_label],
              sinais: r[:signals].map { |s| s[:label] },
              dias_sem_comprar: r[:days_since_purchase], dias_sem_contato: r[:days_since_contact],
              inadimplencia: money(r[:overdue_amount]) }
          },
          aviso: flagged.size > LIMIT ? "Exibindo os #{LIMIT} mais críticos de #{flagged.size}." : nil
        }.compact
      end
    end
  end
end
