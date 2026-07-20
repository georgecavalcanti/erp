module Agent
  module Tools
    # Meta do vendedor no período (doc 06, grupo Consulta). Sem meta cadastrada
    # → ausência explícita (o agente pede cadastro, não inventa valor).
    class ConsultarMeta < BaseTool
      tool_name "consultar_meta"
      description "Consulta a meta do vendedor no período: valor de receita, margem mínima e " \
                  "metas complementares. Sem 'mes', usa o mês corrente."
      input_schema({
        type: "object",
        properties: {
          mes: { type: "string", pattern: "^\\d{4}-\\d{2}$",
                 description: "Mês da meta no formato YYYY-MM (opcional; default: mês corrente)" }
        },
        additionalProperties: false
      })

      def execute(params)
        sp = salesperson!
        period = parse_period(params["mes"])
        goals = Goal.where(salesperson: sp).for_period(period).order(:kind)

        base = { vendedor: sp.nickname, periodo: period.strftime("%Y-%m") }
        if goals.none?
          return base.merge(metas: [],
                            aviso: "Nenhuma meta cadastrada para este período. Peça ao gestor para cadastrar em Administração > Metas.")
        end

        base.merge(metas: goals.map { |g|
          { tipo: g.kind, valor: money(g.amount), margem_minima_percent: money(g.min_margin_percent),
            complementares: g.complementary.presence }.compact
        })
      end

      private

      def parse_period(mes)
        return Date.current.beginning_of_month if mes.blank?

        Date.strptime(mes, "%Y-%m")
      rescue Date::Error
        raise Invalid, "Mês inválido: use o formato YYYY-MM."
      end
    end
  end
end
