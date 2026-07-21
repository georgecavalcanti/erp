module Agent
  module Tools
    # Previsões de recompra do cliente (doc 06, grupo Análise). Devolve as
    # previsões ABERTAS persistidas pelo RepurchaseForecastJob (versionadas,
    # append-only); sem nenhuma → calcula ao vivo sem persistir.
    class PreverRecompra < BaseTool
      tool_name "prever_recompra"
      description "Previsões de recompra de um cliente da carteira (quando e quanto deve comprar de " \
                  "novo, por cliente/categoria/produto), com confiança e atraso. Base para abordagem " \
                  "de recompra."
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
        preds = RepurchasePrediction.status_open.where(partner: partner).order(:expected_date)
        return from_persisted(partner, preds) if preds.any?

        live = Engines::Repurchase.new(partner).call
        products = Product.where(id: live.filter_map { |p| p[:product_id] }).pluck(:id, :description).to_h
        {
          cliente: partner.name, origem: "calculada agora (sem previsão persistida)",
          previsoes: live.map { |p| live_entry(p, products) },
          aviso: live.empty? ? "Histórico insuficiente para prever recompra (mínimo 2 compras)." : nil
        }.compact
      end

      private

      def from_persisted(partner, preds)
        products = Product.where(id: preds.filter_map(&:product_id)).pluck(:id, :description).to_h
        {
          cliente: partner.name, origem: "persistida (motor de recompra)",
          previsoes: preds.map { |p|
            { nivel: p.level, alvo: target_label(p, products), data_esperada: p.expected_date,
              valor_esperado: money(p.expected_value), confianca: p.confidence,
              atrasada_dias: p.expected_date && p.expected_date < Date.current ? (Date.current - p.expected_date).to_i : 0 }
          }
        }
      end

      def target_label(pred, products)
        case pred.level.to_sym
        when :product then products[pred.product_id] || "produto #{pred.product_id}"
        when :category then pred.category_name || "categoria #{pred.category_external_code}"
        else "cliente (compra geral)"
        end
      end

      # Mesmo shape do caminho persistido (alvo + atraso) — sem isso, previsões
      # de categoria/produto ficariam indistinguíveis no fallback ao vivo.
      def live_entry(p, products)
        {
          nivel: p[:level],
          alvo: case p[:level]
                when :product then products[p[:product_id]] || "produto #{p[:product_id]}"
                when :category then p[:category_name] || "categoria #{p[:category_external_code]}"
                else "cliente (compra geral)"
                end,
          data_esperada: p[:expected_date], valor_esperado: money(p[:expected_value]),
          confianca: p[:confidence],
          atrasada_dias: p[:expected_date] && p[:expected_date] < Date.current ? (Date.current - p[:expected_date]).to_i : 0
        }
      end
    end
  end
end
