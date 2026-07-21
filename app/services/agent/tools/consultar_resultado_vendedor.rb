module Agent
  module Tools
    # Posição do vendedor no mês (doc 06): realizado, atingimento, ritmo, gap e os
    # 3 cenários de projeção. Cálculo determinístico ao vivo (Engines::Projection,
    # mesmo motor do Cockpit) — o agente interpreta, não refaz a matemática.
    class ConsultarResultadoVendedor < BaseTool
      tool_name "consultar_resultado_vendedor"
      description "Consulta a posição do vendedor no mês corrente: meta, realizado, % de atingimento, " \
                  "ritmo diário necessário, gap e projeção em 3 cenários (conservador/provável/potencial)."

      def execute(_params)
        sp = salesperson!
        result = Engines::Projection.new(sp).call

        {
          vendedor: sp.nickname,
          mes: result[:reference_date].strftime("%Y-%m"),
          meta: money(result[:target]),
          realizado: money(result[:realized]),
          margem_realizada: money(result[:realized_margin]),
          atingimento_percent: money(result[:attainment_percent]),
          esperado_ate_hoje: money(result[:expected_to_date]),
          ritmo_diario_necessario: money(result[:daily_rhythm_needed]),
          dias_uteis: result[:business_days],
          cenarios: result[:scenarios].transform_values { |s|
            { valor: money(s[:value]), gap: money(s[:gap]), confianca: s[:confidence] }
          },
          aviso: result[:target] ? nil : "Sem meta cadastrada — atingimento e gap indisponíveis."
        }.compact
      end
    end
  end
end
