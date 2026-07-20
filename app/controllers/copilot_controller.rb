# Página do Copiloto Claude (doc 06/08, Sprint 8). O streaming da pergunta fica
# no CopilotStreamsController — ActionController::Live não pode entrar aqui
# (streamaria também o render Inertia).
#
# Escopo: o vendedor conversa sobre a PRÓPRIA carteira; gestor/admin podem abrir
# o copiloto de um vendedor autorizado (mesmo padrão do Plano do Dia).
class CopilotController < ApplicationController
  include CopilotScope

  # Os 5 casos de uso do doc 06 viram sugestões de partida na tela.
  SUGGESTIONS = [
    "Monte meu plano para hoje.",
    "Quais clientes podem cobrir meu gap?",
    "Prepare minha conversa com meu cliente mais prioritário.",
    "Onde estou perdendo margem?",
    "Explique minha projeção."
  ].freeze

  def index
    sp = resolve_salesperson
    last = AgentRun.last_valid(user: Current.user, kind: :copilot)

    render inertia: "Copilot", props: {
      salesperson: sp && { id: sp.id, name: sp.nickname },
      salespeople: selectable_salespeople,
      agentEnabled: Agent::Config.enabled?,
      suggestions: SUGGESTIONS,
      lastResponse: last && {
        resumo: last.output["resumo"],
        recomendacoes: serialize_cards(Recommendation.where(agent_run: last)),
        dados_ausentes: last.output["dados_ausentes"] || [],
        generated_at: last.created_at.iso8601
      }
    }
  end
end
