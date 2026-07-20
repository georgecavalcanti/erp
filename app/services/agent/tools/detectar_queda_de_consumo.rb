module Agent
  module Tools
    # Queda de consumo na carteira (doc 06, grupo Análise): compara o ritmo
    # recente com a linha de base de cada cliente (Engines::ConsumptionDrop) e
    # devolve quem está caindo, ordenado pela perda absoluta.
    class DetectarQuedaDeConsumo < BaseTool
      tool_name "detectar_queda_de_consumo"
      description "Clientes da carteira com queda de consumo: ritmo recente vs. linha de base, " \
                  "% de queda e valor perdido estimado, dos maiores para os menores."

      LIMIT = 15

      def execute(_params)
        sp = salesperson!
        ids = Wallet.active.where(salesperson: sp).distinct.pluck(:partner_id)
        return { clientes: [], aviso: "Carteira vazia — nenhum cliente vinculado." } if ids.empty?

        names = Partner.where(id: ids).pluck(:id, :name).to_h
        dropping = Engines::ConsumptionDrop.for_partners(ids)
                                           .select { |_id, c| c[:trend] == :drop }
                                           .sort_by { |_id, c| -c[:absolute_lost] }

        {
          carteira: ids.size,
          em_queda: dropping.size,
          clientes: dropping.first(LIMIT).map { |id, c|
            { partner_id: id, cliente: names[id], queda_percent: c[:drop_percent],
              ritmo_recente: money(c[:recent_net]), linha_de_base: money(c[:baseline_net]),
              perda_estimada: money(c[:absolute_lost]) }
          }
        }
      end
    end
  end
end
