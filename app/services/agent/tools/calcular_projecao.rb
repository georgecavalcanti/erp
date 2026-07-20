module Agent
  module Tools
    # Projeção do mês (doc 06, grupo Análise). Regra do grupo: devolve o resultado
    # PERSISTIDO/versionado do motor (leva mais recente do ProjectionRecalcJob),
    # com as parcelas rastreáveis — o agente explica, não refaz a matemática.
    # Sem leva persistida do mês → calcula ao vivo (determinístico) sem persistir.
    class CalcularProjecao < BaseTool
      tool_name "calcular_projecao"
      description "Projeção de faturamento do mês do vendedor em 3 cenários (conservador/provável/" \
                  "potencial), com as parcelas que compõem cada um (realizado, carteira, ritmo). " \
                  "Use para explicar COMO a projeção foi construída."

      def execute(_params)
        sp = salesperson!
        persisted = latest_batch(sp)
        return from_persisted(sp, persisted) if persisted.any?

        live = Engines::Projection.new(sp).call
        {
          vendedor: sp.nickname, origem: "calculada agora (sem leva persistida no mês)",
          meta: money(live[:target]), realizado: money(live[:realized]),
          cenarios: live[:scenarios].map { |name, s|
            { cenario: name, valor: money(s[:value]), gap: money(s[:gap]),
              confianca: s[:confidence], parcelas: s[:components] }
          }
        }
      end

      private

      # Leva = os 3 cenários gravados juntos; pega a mais recente do mês corrente.
      def latest_batch(sp)
        newest = ::Projection.where(salesperson: sp, reference_date: Date.current.all_month)
                             .order(created_at: :desc).first
        return [] unless newest

        ::Projection.where(salesperson: sp, reference_date: newest.reference_date)
                    .where(created_at: (newest.created_at - 5.seconds)..newest.created_at)
      end

      def from_persisted(sp, batch)
        first = batch.first
        {
          vendedor: sp.nickname,
          origem: "persistida em #{first.created_at.iso8601} (versão #{first.engine_version})",
          referencia: first.reference_date,
          meta: money(first.target_value), realizado: money(first.realized_value),
          cenarios: batch.sort_by(&:scenario).map { |p|
            { cenario: p.scenario, valor: money(p.value), margem: money(p.margin_value),
              gap: money(p.gap_value), confianca: p.confidence, parcelas: p.components["parcels"] }
          }
        }
      end
    end
  end
end
