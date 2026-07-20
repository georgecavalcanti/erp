module Agent
  # Orquestrador do agente (doc 06): o loop de tool use com a Claude API.
  #
  #   Agent::Orchestrator.new(user:, salesperson:, kind: :copilot)
  #     .run("Monte meu plano para hoje")
  #   # => Agent::Orchestrator::Result
  #
  # Responsabilidades (e por que o loop é MANUAL, não o tool_runner da gem):
  #   * allowlist em ação: toda chamada passa pelo ToolRegistry (fora dele = erro);
  #   * auditoria: cada ferramenta com parâmetros/duração em agent_runs.tools_called;
  #   * teto diário de tokens verificado ANTES de chamar a API (alerta a 80%);
  #   * tiering de modelo por complexidade (Haiku rotina / Sonnet complexo);
  #   * prompt caching (bloco institucional + ferramentas em ordem estável);
  #   * structured output do formato de recomendação, com retry limitado —
  #     resposta fora do schema → status invalid_schema (doc 09);
  #   * degradação: sem chave/teto estourado/erro → última resposta válida + aviso.
  #
  # O cliente da API é INJETÁVEL (testes usam FakeClaudeClient — nunca rede).
  class Orchestrator
    MAX_TOOL_ROUNDS = 8     # teto de idas e voltas de ferramenta numa pergunta
    MAX_SCHEMA_RETRIES = 1  # resposta fora do schema → 1 retry, depois invalid_schema
    # No Sonnet 5 o adaptive thinking (ligado por padrão) consome DESTE teto —
    # 4096 truncaria a resposta final com facilidade (revisão cruzada Sprint 8).
    MAX_TOKENS = 8192

    # Formato padrão de recomendação (doc 06) imposto por structured output.
    # (Structured outputs não suportam minimum/maximum — confiança é clampada
    # na validação local.)
    RESPONSE_SCHEMA = {
      type: "object",
      properties: {
        resumo: { type: "string", description: "Resposta ao vendedor, pronta para exibição" },
        recomendacoes: {
          type: "array",
          items: {
            type: "object",
            properties: {
              diagnostico: { type: "string" },
              recomendacao: { type: "string" },
              evidencias: { type: "array", items: { type: "string" } },
              impacto_potencial: {
                type: "object",
                properties: { receita: { type: "number" }, margem: { type: "number" },
                              retencao: { type: "string" } },
                additionalProperties: false
              },
              confianca: { type: "integer" },
              proxima_acao: { type: "string" },
              canal: { type: "string", enum: %w[call whatsapp visit email internal] },
              prazo: { type: "string" },
              restricoes: { type: "array", items: { type: "string" } },
              partner_id: { type: "integer" }
            },
            required: %w[diagnostico recomendacao evidencias confianca proxima_acao],
            additionalProperties: false
          }
        },
        dados_ausentes: { type: "array", items: { type: "string" } },
        # Abordagens para cards JÁ existentes do plano do dia (U6): o id vem da
        # lista fornecida pela aplicação no prompt — nunca inventado pelo modelo
        # (a persistência revalida o dono do card).
        abordagens: {
          type: "array",
          items: {
            type: "object",
            properties: {
              recommendation_id: { type: "integer" },
              abordagem: { type: "string" }
            },
            required: %w[recommendation_id abordagem],
            additionalProperties: false
          }
        }
      },
      required: %w[resumo recomendacoes],
      additionalProperties: false
    }.freeze

    # Resultado devolvido às telas. degraded=true → resumo é a última resposta
    # válida (ou aviso), com generated_at original para o carimbo "gerado às".
    Result = Struct.new(:status, :resumo, :recomendacoes, :dados_ausentes,
                        :degraded, :aviso, :agent_run, :generated_at, keyword_init: true)

    def initialize(user:, salesperson: nil, kind: :copilot, client: nil)
      @user = user
      @salesperson = salesperson
      @kind = kind
      @client = client || Anthropic::Client.new(api_key: Config.api_key)
      @registry = ToolRegistry.new(user: user, salesperson: salesperson)
      @context = ContextBuilder.new(user: user, salesperson: salesperson)
    end

    # Executa uma pergunta. `history` = turnos anteriores da conversa (formato da
    # API). `on_event` recebe o progresso para streaming: (:tool, nome),
    # (:thinking, nil) a cada chamada do modelo.
    def run(question, history: [], on_event: nil)
      # Normaliza o encoding na porta de entrada (input pode chegar binário de
      # runner/console); sem isso o match de complexidade explode em UTF-8.
      question = question.to_s.dup.force_encoding(Encoding::UTF_8).scrub

      return degraded("IA não configurada (ANTHROPIC_API_KEY ausente).") unless Config.enabled?
      return budget_exceeded_result if budget_exceeded?

      warn_budget_if_needed
      execute(question, history, on_event)
    end

    private

    # ---- Loop principal --------------------------------------------------------

    def execute(question, history, on_event)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      model = select_model(question)
      messages = history + [ { role: "user", content: question } ]
      tools_called = []
      usage = Hash.new(0)
      schema_retries = 0

      MAX_TOOL_ROUNDS.times do
        on_event&.call(:thinking, nil)
        response = request(model, messages)
        track_usage(usage, response)

        if response.stop_reason == :refusal
          return persist_and_build(status: :refused, output: nil, model:, usage:, tools_called:,
                                   question:, started:, aviso: "A IA recusou esta pergunta.")
        end
        # Resposta cortada pelo teto de tokens: o JSON veio truncado — retry
        # seria custo jogado fora (viria truncado de novo). Falha explícita.
        if response.stop_reason == :max_tokens
          return persist_and_build(status: :error, output: nil, model:, usage:, tools_called:,
                                   question:, started:,
                                   aviso: "A resposta excedeu o limite de tamanho — reformule a pergunta em partes menores.")
        end

        messages << { role: "assistant", content: serialize_content(response.content) }

        tool_uses = response.content.select { |b| b.type == :tool_use }
        if tool_uses.any?
          messages << { role: "user", content: run_tools(tool_uses, tools_called, on_event) }
          next
        end

        # Sem tool_use: é a resposta final (JSON do schema). Valida localmente;
        # fora do schema → pede correção uma vez, depois invalid_schema.
        output = parse_output(response.content)
        if output
          return persist_and_build(status: :ok, output:, model:, usage:, tools_called:,
                                   question:, started:)
        end

        schema_retries += 1
        if schema_retries > MAX_SCHEMA_RETRIES
          return persist_and_build(status: :invalid_schema, output: nil, model:, usage:,
                                   tools_called:, question:, started:,
                                   aviso: "A IA respondeu fora do formato esperado.")
        end
        messages << { role: "user",
                      content: "Sua resposta não seguiu o schema JSON exigido. Responda novamente " \
                               "APENAS com o JSON válido (campos: resumo, recomendacoes, dados_ausentes)." }
      end

      persist_and_build(status: :error, output: nil, model:, usage:, tools_called:,
                        question:, started:, aviso: "A conversa excedeu o limite de ferramentas.")
    rescue Anthropic::Errors::APIError => e
      Rails.logger.error("[Agent::Orchestrator] API: #{e.class} #{e.message}")
      persist_and_build(status: :error, output: nil, model: model, usage: usage,
                        tools_called: tools_called, question: question, started: started,
                        aviso: "IA indisponível no momento.",
                        error_detail: "#{e.class}: #{e.message}".truncate(500))
    end

    def request(model, messages)
      @client.messages.create(
        model: model,
        max_tokens: MAX_TOKENS,
        system_: @context.system_blocks,
        tools: @registry.definitions,
        messages: messages,
        output_config: { format: { type: "json_schema", schema: RESPONSE_SCHEMA } }
      )
    end

    # Executa as ferramentas pedidas (allowlist + escopo no registry), medindo a
    # duração de cada uma para a auditoria. Erro vira tool_result is_error.
    def run_tools(tool_uses, tools_called, on_event)
      tool_uses.map do |block|
        on_event&.call(:tool, block.name)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = @registry.call(block.name, block.input.to_h)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        tools_called << { name: block.name, params: block.input.to_h,
                          duration_ms: duration_ms, ok: result[:ok] }

        { type: "tool_result", tool_use_id: block.id,
          content: JSON.generate(result[:ok] ? result[:data] : { erro: result[:error] }),
          is_error: !result[:ok] }
      end
    end

    # Reserializa os blocos da resposta para reenviá-los como turno assistant.
    # Blocos thinking DEVEM voltar intactos (com signature): no Sonnet 5 o
    # adaptive thinking é ligado por padrão e a API rejeita (400) um turno
    # assistant com tool_use cujo thinking foi removido — descartá-los quebraria
    # todo o loop de ferramentas do tier complexo (revisão cruzada Sprint 8).
    def serialize_content(content)
      content.map do |block|
        case block.type
        when :text then { type: "text", text: block.text }
        when :tool_use then { type: "tool_use", id: block.id, name: block.name, input: block.input.to_h }
        when :thinking then { type: "thinking", thinking: block.thinking, signature: block.signature }
        when :redacted_thinking then { type: "redacted_thinking", data: block.data }
        end
      end.compact
    end

    # ---- Structured output -----------------------------------------------------

    # Extrai e valida o JSON final. nil = fora do schema (dispara retry).
    def parse_output(content)
      text = content.select { |b| b.type == :text }.map(&:text).join
      return nil if text.blank?

      data = JSON.parse(text)
      return nil unless data.is_a?(Hash) && data["resumo"].is_a?(String) && data["recomendacoes"].is_a?(Array)

      data["recomendacoes"] = data["recomendacoes"].filter_map { |r| normalize_recommendation(r) }
      data["dados_ausentes"] = Array(data["dados_ausentes"]).map(&:to_s)
      data["abordagens"] = Array(data["abordagens"]).select { |a|
        a.is_a?(Hash) && a["recommendation_id"].present? && a["abordagem"].present?
      }
      data
    rescue JSON::ParserError
      nil
    end

    # Campos mínimos do formato (doc 06); confiança clampada em 0..100.
    def normalize_recommendation(rec)
      return nil unless rec.is_a?(Hash) && rec["diagnostico"].present? && rec["recomendacao"].present?

      rec["confianca"] = rec["confianca"].to_i.clamp(0, 100)
      rec["evidencias"] = Array(rec["evidencias"]).map(&:to_s)
      rec["restricoes"] = Array(rec["restricoes"]).map(&:to_s)
      rec
    end

    # ---- Persistência (agent_runs + recommendations) ---------------------------

    def persist_and_build(status:, output:, model:, usage:, tools_called:, question:, started:,
                          aviso: nil, error_detail: nil)
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      run = AgentRun.create!(
        user: @user, salesperson: @salesperson, kind: @kind, status: status, model: model,
        prompt_summary: question.to_s.truncate(200),
        tools_called: tools_called,
        input_tokens: usage[:input], output_tokens: usage[:output],
        cache_read_tokens: usage[:cache_read], cache_write_tokens: usage[:cache_write],
        cost_estimate: Config.cost_estimate(model: model, input_tokens: usage[:input],
                                            output_tokens: usage[:output],
                                            cache_read_tokens: usage[:cache_read],
                                            cache_write_tokens: usage[:cache_write]),
        latency_ms: latency_ms,
        error_detail: error_detail || aviso,
        response_digest: output && Digest::SHA256.hexdigest(output.to_json),
        output: output
      )

      if status == :ok && output
        persist_recommendations(run, output)
        persist_approaches(run, output)
      end
      return degraded(aviso, error_run: run) unless status == :ok

      Result.new(status: :ok, resumo: output["resumo"], recomendacoes: output["recomendacoes"],
                 dados_ausentes: output["dados_ausentes"], degraded: false,
                 agent_run: run, generated_at: run.created_at)
    end

    # Cada recomendação do output vira um card persistido (doc 06: formato padrão
    # em recommendations com tools_used + agent_run_id). O partner_id é validado
    # contra a CARTEIRA DO VENDEDOR DE CONTEXTO — não contra a política do
    # usuário: um gestor irrestrito operando o copiloto de A não pode gravar no
    # plano de A um card com cliente de B (revisão cruzada Sprint 8). Id fora da
    # carteira (ou alucinado) vira nil — nunca derruba o run.
    def persist_recommendations(run, output)
      return if @salesperson.nil?

      wallet_ids = Wallet.active.where(salesperson_id: @salesperson.id).distinct.pluck(:partner_id)
      output["recomendacoes"].each do |rec|
        partner_id = rec["partner_id"]
        partner_id = nil unless partner_id && wallet_ids.include?(partner_id.to_i)

        # Índice único (vendedor, cliente, dia): se o card determinístico do
        # cliente já existe no plano, não duplica (o texto segue no resumo).
        next if partner_id && Recommendation.for_date(Date.current)
                                            .exists?(salesperson_id: @salesperson.id, partner_id: partner_id)

        Recommendation.create!(
          user: @user, salesperson: @salesperson, partner_id: partner_id,
          reference_date: Date.current, agent_run: run,
          diagnosis: rec["diagnostico"], recommendation: rec["recomendacao"],
          evidences: rec["evidencias"], potential_impact: rec["impacto_potencial"] || {},
          confidence: rec["confianca"], next_action: rec["proxima_acao"],
          channel: rec["canal"], deadline: parse_date(rec["prazo"]),
          restrictions: rec["restricoes"],
          tools_used: run.tools_called.map { |t| t[:name] || t["name"] }.uniq,
          status: :pending
        )
      rescue ActiveRecord::RecordNotUnique
        # Corrida com o job de priorização criando o card do mesmo cliente —
        # o card determinístico vence; o run não pode falhar por isso.
        next
      end
    end

    # Abordagens escrevem no card EXISTENTE — só de cards ABERTOS DE HOJE do
    # vendedor do contexto (id fora do escopo/data é ignorado; um id alucinado
    # não pode sobrescrever abordagem de card antigo — revisão cruzada Sprint 8).
    def persist_approaches(run, output)
      return if @salesperson.nil? || output["abordagens"].blank?

      output["abordagens"].each do |item|
        Recommendation.for_date(Date.current)
                      .where(id: item["recommendation_id"], salesperson_id: @salesperson.id,
                             status: %i[pending accepted])
                      .update_all(approach: item["abordagem"], agent_run_id: run.id, updated_at: Time.current)
      end
    end

    def parse_date(value)
      value.present? ? Date.iso8601(value) : nil
    rescue Date::Error
      nil
    end

    # ---- Modelo, teto e degradação ---------------------------------------------

    # Tiering (doc 06): Haiku para rotina; Sonnet para o complexo. Resumo do
    # cockpit e abordagens do plano são sempre rotina; simulação é sempre
    # complexa; no copiloto decide pela pergunta.
    COMPLEX_HINTS = /simul|compar|estratégi|explique|por que|porque|cenário|margem/i

    def select_model(question)
      case @kind.to_sym
      when :cockpit_summary, :daily_plan, :batch then Config.light_model
      when :simulation then Config.default_model
      else
        (question.to_s.length > 280 || question.to_s.match?(COMPLEX_HINTS)) ? Config.default_model : Config.light_model
      end
    end

    def track_usage(usage, response)
      u = response.usage
      usage[:input] += u.input_tokens.to_i
      usage[:output] += u.output_tokens.to_i
      usage[:cache_read] += u.respond_to?(:cache_read_input_tokens) ? u.cache_read_input_tokens.to_i : 0
      # Escrita de cache é COBRADA (1,25× do input) — entra no custo e no teto.
      usage[:cache_write] += u.respond_to?(:cache_creation_input_tokens) ? u.cache_creation_input_tokens.to_i : 0
    end

    def budget_exceeded?
      AgentRun.tokens_spent_today >= Config.daily_token_budget
    end

    def budget_exceeded_result
      register_budget_alert(:high, "Teto diário de tokens excedido",
                            "O agente foi pausado até amanhã (AGENT_DAILY_TOKEN_BUDGET).")
      degraded("Teto diário de uso da IA atingido — o copiloto volta amanhã.")
    end

    # Alerta (grupo IA, doc 09) ao cruzar 80% do teto — uma vez por dia.
    def warn_budget_if_needed
      spent = AgentRun.tokens_spent_today
      return if spent < Config.daily_token_budget * Config.budget_warning_ratio

      register_budget_alert(:medium, "Orçamento diário de tokens em #{(spent * 100 / Config.daily_token_budget)}%",
                            "Aproximando do teto AGENT_DAILY_TOKEN_BUDGET (#{Config.daily_token_budget}).")
    end

    def register_budget_alert(severity, title, message)
      key = "agent_budget:#{Date.current.iso8601}:#{severity}"
      alert = Alert.open.find_or_initialize_by(key: key)
      alert.assign_attributes(area: :ia, severity: severity, title: title, message: message,
                              first_detected_at: alert.first_detected_at || Time.current,
                              last_detected_at: Time.current)
      alert.save!
    rescue StandardError => e
      Rails.logger.error("[Agent::Orchestrator] alerta de teto falhou: #{e.message}")
    end

    # Resposta degradada (doc 06, resiliência): a ÚLTIMA resposta válida do mesmo
    # tipo E MESMO VENDEDOR de contexto (gestor alternando carteiras não vê a
    # resposta de A em B), com aviso e carimbo. Sem histórico → só o aviso.
    def degraded(aviso, error_run: nil)
      last = AgentRun.last_valid(user: @user, kind: @kind, salesperson: @salesperson)
      if last
        Result.new(status: :degraded, resumo: last.output["resumo"],
                   recomendacoes: last.output["recomendacoes"] || [],
                   dados_ausentes: last.output["dados_ausentes"] || [],
                   degraded: true, aviso: aviso, agent_run: error_run || last,
                   generated_at: last.created_at)
      else
        Result.new(status: :degraded, resumo: nil, recomendacoes: [], dados_ausentes: [],
                   degraded: true, aviso: aviso, agent_run: error_run, generated_at: nil)
      end
    end
  end
end
