module Agent
  module Tools
    # Simulador de meta (doc 06, grupo Análise): o MENOR conjunto de clientes/
    # oportunidades cujo valor esperado cobre o gap, respeitando a capacidade
    # diária (Engines::GoalSimulator — guloso, determinístico).
    class SimularPlanoParaMeta < BaseTool
      tool_name "simular_plano_para_meta"
      description "Simula a combinação de clientes e oportunidades capaz de cobrir o gap da meta do " \
                  "vendedor, com valor esperado (potencial × probabilidade), origem de cada oportunidade " \
                  "e se o gap fecha dentro da capacidade diária."

      def execute(_params)
        sp = salesperson!
        result = Engines::GoalSimulator.new(sp).call
        names = Partner.where(id: result[:selected].map { |o| o[:partner_id] }).pluck(:id, :name).to_h

        {
          vendedor: sp.nickname,
          gap: money(result[:gap]),
          capacidade_diaria: result[:capacity],
          valor_esperado_total: money(result[:projected]),
          cobre_o_gap: result[:covers_gap],
          oportunidades: result[:selected].map { |o|
            { partner_id: o[:partner_id], cliente: names[o[:partner_id]],
              potencial: money(o[:potential]), probabilidade: o[:probability],
              valor_esperado: money(o[:expected]), origem: o[:origin] }
          },
          por_origem: result[:by_origin],
          aviso: result[:gap].nil? ? "Sem meta cadastrada — simulação lista as melhores oportunidades, sem gap de referência." : nil
        }.compact
      end
    end
  end
end
