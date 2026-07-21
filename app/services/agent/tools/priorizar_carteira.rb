module Agent
  module Tools
    # Priorização da carteira (doc 06, grupo Análise). Devolve o plano PERSISTIDO
    # do dia (PriorityRecalcJob) — mesmo ranking da tela Plano do Dia. Sem plano
    # persistido → calcula ao vivo (determinístico) sem persistir.
    class PriorizarCarteira < BaseTool
      tool_name "priorizar_carteira"
      description "Ranking de prioridade da carteira do vendedor para hoje: score, motivos, potencial, " \
                  "urgência, ação sugerida e restrições de cada cliente — a base do plano do dia."

      LIMIT = 15

      def execute(_params)
        sp = salesperson!
        persisted = Priority.for_date(Date.current).where(salesperson: sp).order(:position).limit(LIMIT)
        return from_persisted(sp, persisted) if persisted.any?

        items = Engines::Prioritization.new(sp).call.first(LIMIT)
        names = Partner.where(id: items.map { |i| i[:partner_id] }).pluck(:id, :name).to_h
        {
          vendedor: sp.nickname, origem: "calculada agora (sem plano persistido hoje)",
          prioridades: items.map { |it|
            { posicao: it[:position], partner_id: it[:partner_id], cliente: names[it[:partner_id]],
              score: it[:score], motivos: it[:reasons].map { |r| r[:label] || r[:key] },
              potencial: money(it[:potential_value]), urgencia: it[:urgency],
              acao_sugerida: it[:suggested_action],
              restricoes: it[:restrictions].map { |r| r[:label] || r[:key] } }
          }
        }
      end

      private

      def from_persisted(sp, priorities)
        names = Partner.where(id: priorities.map(&:partner_id)).pluck(:id, :name).to_h
        {
          vendedor: sp.nickname, origem: "plano persistido de hoje",
          prioridades: priorities.map { |p|
            { posicao: p.position, partner_id: p.partner_id, cliente: names[p.partner_id],
              score: p.score.to_f, motivos: Array(p.reasons).map { |r| r["label"] || r["key"] },
              potencial: money(p.potential_value), urgencia: p.urgency,
              acao_sugerida: p.suggested_action,
              restricoes: Array(p.restrictions).map { |r| r["label"] || r["key"] } }
          }
        }
      end
    end
  end
end
