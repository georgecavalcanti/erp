# SSE do copiloto (Sprint 8): POST /copiloto/perguntar. Controller SEPARADO da
# página porque ActionController::Live muda o pipeline de resposta de TODAS as
# ações do controller (streaming em thread própria — quebraria o render Inertia).
#
# Eventos: `status` (ferramenta em execução — streaming de progresso),
# `result` (resposta final estruturada) e `error`. O stream sempre fecha; o
# front abre um por pergunta.
class CopilotStreamsController < ApplicationController
  include ActionController::Live
  include CopilotScope

  def create
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["Last-Modified"] = Time.current.httpdate # evita buffering do Rack::ETag

    question = params[:question].to_s
    return sse(:error, message: "Pergunta vazia.") if question.blank?

    result = Agent::Orchestrator.new(user: Current.user, salesperson: resolve_salesperson, kind: :copilot)
                                .run(question, history: history_from_params,
                                     on_event: ->(type, tool) { sse(:status, type: type, tool: tool) })

    sse(:result, serialize_result(result))
  rescue ActionController::Live::ClientDisconnected, IOError
    # Cliente fechou a aba no meio — o run já persistiu em agent_runs.
  ensure
    response.stream.close
  end

  private

  # Reconstrói o histórico curto enviado pelo front (últimos turnos) no formato
  # da API. Conteúdo é só texto (pergunta + resumo exibido) — suficiente para
  # continuidade sem reenviar tool_results.
  def history_from_params
    Array(params[:history]).last(6).filter_map do |turn|
      role = turn[:role].to_s
      next unless %w[user assistant].include?(role) && turn[:content].present?

      { role: role, content: turn[:content].to_s.truncate(2_000) }
    end
  end

  def serialize_result(result)
    cards = result.agent_run ? serialize_cards(Recommendation.where(agent_run: result.agent_run)) : []
    {
      status: result.status,
      degraded: result.degraded,
      aviso: result.aviso,
      resumo: result.resumo,
      recomendacoes: cards,
      dados_ausentes: result.dados_ausentes || [],
      generated_at: result.generated_at&.iso8601
    }
  end

  # Escrita tolerante a desconexão: se o cliente fechou a aba no meio do loop,
  # os writes seguintes viram no-op — o run COMPLETA e persiste em agent_runs
  # (tokens gastos não podem escapar do teto/auditoria — revisão cruzada S8).
  def sse(event, data)
    return if @client_gone

    response.stream.write("event: #{event}\ndata: #{JSON.generate(data)}\n\n")
  rescue ActionController::Live::ClientDisconnected, IOError
    @client_gone = true
  end
end
