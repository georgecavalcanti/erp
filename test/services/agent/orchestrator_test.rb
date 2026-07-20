require "test_helper"
require_relative "../../test_helpers/fake_claude_client"

module Agent
  # Orquestrador (doc 06/10). Categorias obrigatórias do doc 10 com MOCK da API:
  # uso correto das ferramentas, dados conflitantes, ausência de dados (não
  # inventa), esquema inválido (retry + status) e ações fora do registry.
  class OrchestratorTest < ActiveSupport::TestCase
    setup do
      # Chave fake: o cliente é injetado, mas Config.enabled? precisa passar.
      ENV["ANTHROPIC_API_KEY"] = "sk-teste-fake"

      @sp = Salesperson.create!(external_code: 96_001, nickname: "VEND.ORQ")
      @user = User.create!(email_address: "orq@teste.local", password: "senha-secreta",
                           role: :vendedor, salesperson: @sp)
      @cliente = Partner.create!(external_code: 96_101, name: "Cliente Orq")
      Wallet.create!(salesperson: @sp, partner: @cliente, starts_on: 1.year.ago)
    end

    teardown do
      ENV.delete("ANTHROPIC_API_KEY")
      ENV.delete("AGENT_DAILY_TOKEN_BUDGET")
    end

    VALID_OUTPUT = {
      resumo: "Seu gap está em R$ 12.000; priorize o Cliente Orq.",
      recomendacoes: [
        { diagnostico: "Recompra atrasada há 10 dias", recomendacao: "Oferecer reposição do mix",
          evidencias: [ "previsão de recompra vencida em 10/07" ], confianca: 80,
          proxima_acao: "Ligar hoje", canal: "call", prazo: Date.current.iso8601,
          restricoes: [], partner_id: nil }
      ],
      dados_ausentes: []
    }.freeze

    def orchestrator(client, kind: :copilot)
      Orchestrator.new(user: @user, salesperson: @sp, kind: kind, client: client)
    end

    # ---- Uso correto das ferramentas ----------------------------------------

    test "loop executa a ferramenta pedida e devolve o resultado ao modelo" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "consultar_meta", {} ]),
        FakeClaudeClient.final(VALID_OUTPUT)
      ])

      result = orchestrator(fake).run("Qual minha meta?")

      assert_equal :ok, result.status
      # A 2ª request carrega o tool_result da 1ª ferramenta.
      second = fake.requests.last
      tool_result = second[:messages].last[:content].first
      assert_equal "tool_result", tool_result[:type]
      assert_equal "toolu_1", tool_result[:tool_use_id]
      assert_not tool_result[:is_error]
      # Auditoria: ferramenta com nome/duração no agent_run.
      run = result.agent_run
      assert_equal "consultar_meta", run.tools_called.first["name"]
      assert run.tools_called.first["duration_ms"].is_a?(Integer)
      assert_equal "ok", run.status
    end

    test "recomendações do output viram cards persistidos com agent_run e tools_used" do
      output = VALID_OUTPUT.deep_dup
      output[:recomendacoes][0][:partner_id] = @cliente.id
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "prever_recompra", { "partner_id" => @cliente.id } ]),
        FakeClaudeClient.final(output)
      ])

      result = orchestrator(fake).run("Prepare minha conversa com o Cliente Orq")

      rec = Recommendation.find_by(agent_run: result.agent_run)
      assert rec.present?
      assert_equal @cliente.id, rec.partner_id
      assert_equal "Recompra atrasada há 10 dias", rec.diagnosis
      assert_includes rec.tools_used, "prever_recompra"
      assert rec.status_pending?
    end

    test "partner_id fora da carteira não é gravado no card (modelo não escolhe escopo)" do
      alheio = Partner.create!(external_code: 96_102, name: "Alheio")
      output = VALID_OUTPUT.deep_dup
      output[:recomendacoes][0][:partner_id] = alheio.id

      fake = FakeClaudeClient.new([ FakeClaudeClient.final(output) ])
      result = orchestrator(fake).run("plano")

      rec = Recommendation.find_by(agent_run: result.agent_run)
      assert_nil rec.partner_id, "cliente fora da carteira não pode ser vinculado"
    end

    # ---- Dados conflitantes: tudo chega ao modelo sem filtro ----------------

    test "resultados de várias ferramentas (mesmo conflitantes) são repassados na íntegra" do
      Goal.create!(salesperson: @sp, period: Date.current, kind: :revenue, amount: 100_000)
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "consultar_meta", {} ], [ "consultar_resultado_vendedor", {} ]),
        FakeClaudeClient.final(VALID_OUTPUT)
      ])

      orchestrator(fake).run("Compare minha meta com o resultado")

      results = fake.requests.last[:messages].last[:content]
      assert_equal 2, results.size, "um tool_result por ferramenta, na mesma mensagem"
      assert results.none? { |r| r[:is_error] }
      payloads = results.map { |r| JSON.parse(r[:content]) }
      assert_equal 100_000.0, payloads.first["metas"].first["valor"]
      assert payloads.last.key?("realizado")
    end

    # ---- Ausência de dados ---------------------------------------------------

    test "ausência de dados flui da ferramenta ao resultado (não inventa)" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "consultar_meta", {} ]),
        FakeClaudeClient.final(VALID_OUTPUT.merge(
          resumo: "Você não tem meta cadastrada para julho — peça ao gestor.",
          recomendacoes: [], dados_ausentes: [ "meta de julho não cadastrada" ]
        ))
      ])

      result = orchestrator(fake).run("Qual minha meta?")

      # A ferramenta declarou a ausência no tool_result…
      tool_payload = JSON.parse(fake.requests.last[:messages].last[:content].first[:content])
      assert_match(/Nenhuma meta cadastrada/, tool_payload["aviso"])
      # …e o resultado final carrega dados_ausentes.
      assert_equal [ "meta de julho não cadastrada" ], result.dados_ausentes
      assert_empty result.recomendacoes
    end

    # ---- Esquema inválido: retry + status -----------------------------------

    test "resposta fora do schema ganha 1 retry e depois vira invalid_schema" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.final("isto não é JSON"),
        FakeClaudeClient.final("{ ainda quebrado")
      ])

      result = orchestrator(fake).run("pergunta")

      assert result.degraded
      assert_equal "invalid_schema", AgentRun.order(:id).last.status
      # O retry pediu correção explicitamente.
      retry_msg = fake.requests.last[:messages].last
      assert_equal "user", retry_msg[:role]
      assert_match(/schema JSON/, retry_msg[:content])
    end

    test "retry que corrige o schema termina ok" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.final("não é JSON"),
        FakeClaudeClient.final(VALID_OUTPUT)
      ])

      result = orchestrator(fake).run("pergunta")
      assert_equal :ok, result.status
      assert_equal "ok", result.agent_run.status
    end

    # ---- Ações fora do registry ---------------------------------------------

    test "ferramenta fora da allowlist vira tool_result de erro e o loop segue" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "alterar_preco", { "produto" => 1, "preco" => 9.9 } ]),
        FakeClaudeClient.final(VALID_OUTPUT.merge(recomendacoes: []))
      ])

      result = orchestrator(fake).run("Baixa o preço aí")

      assert_equal :ok, result.status
      err = fake.requests.last[:messages].last[:content].first
      assert err[:is_error]
      assert_match(/não existe/, JSON.parse(err[:content])["erro"])
      assert_equal false, result.agent_run.tools_called.first["ok"]
    end

    # ---- Teto diário, refusal e degradação ----------------------------------

    test "teto diário estourado degrada SEM chamar a API e registra alerta" do
      ENV["AGENT_DAILY_TOKEN_BUDGET"] = "1000"
      AgentRun.create!(user: @user, kind: :copilot, status: :ok, input_tokens: 900, output_tokens: 200)
      fake = FakeClaudeClient.new([]) # qualquer request estouraria o roteiro

      result = orchestrator(fake).run("pergunta")

      assert result.degraded
      assert_match(/Teto diário/, result.aviso)
      assert_empty fake.requests
      assert Alert.area_ia.severity_high.exists?
    end

    test "degradação devolve a última resposta válida com carimbo original" do
      old = AgentRun.create!(user: @user, kind: :copilot, status: :ok,
                             output: { "resumo" => "Resposta de ontem", "recomendacoes" => [] },
                             created_at: 1.day.ago)
      ENV.delete("ANTHROPIC_API_KEY") # IA desconfigurada

      result = orchestrator(FakeClaudeClient.new([])).run("pergunta")

      assert result.degraded
      assert_equal "Resposta de ontem", result.resumo
      assert_equal old.created_at.to_i, result.generated_at.to_i
    end

    test "refusal vira status refused com aviso" do
      fake = FakeClaudeClient.new([ FakeClaudeClient.refusal ])
      result = orchestrator(fake).run("pergunta imprópria")

      assert result.degraded
      assert_equal "refused", AgentRun.order(:id).last.status
    end

    # ---- Custos: caching, tiering e contabilidade ---------------------------

    test "prompt tem bloco institucional cacheável e tools em ordem estável" do
      fake = FakeClaudeClient.new([ FakeClaudeClient.final(VALID_OUTPUT) ])
      orchestrator(fake).run("oi")

      req = fake.requests.first
      assert_equal({ type: "ephemeral" }, req[:system_].first[:cache_control])
      assert_nil req[:system_].last[:cache_control], "bloco volátil fica fora do cache"
      assert_equal 24, req[:tools].size
      assert_equal req[:tools].map { |t| t[:name] },
                   ToolRegistry.new(user: @user).definitions.map { |t| t[:name] }
      assert_equal "json_schema", req.dig(:output_config, :format, :type)
    end

    test "tiering: rotina usa Haiku, pergunta complexa e simulação usam Sonnet" do
      curta = FakeClaudeClient.new([ FakeClaudeClient.final(VALID_OUTPUT) ])
      orchestrator(curta).run("Qual minha meta?")
      assert_equal Config.light_model, curta.requests.first[:model]

      complexa = FakeClaudeClient.new([ FakeClaudeClient.final(VALID_OUTPUT) ])
      orchestrator(complexa).run("Explique minha projeção e compare os cenários")
      assert_equal Config.default_model, complexa.requests.first[:model]

      sim = FakeClaudeClient.new([ FakeClaudeClient.final(VALID_OUTPUT) ])
      orchestrator(sim, kind: :simulation).run("oi")
      assert_equal Config.default_model, sim.requests.first[:model]
    end

    test "tokens de todas as idas somam no agent_run com custo estimado" do
      fake = FakeClaudeClient.new([
        FakeClaudeClient.tool_use([ "consultar_meta", {} ], usage: [ 1_000, 100, 500 ]),
        FakeClaudeClient.final(VALID_OUTPUT, usage: [ 2_000, 300, 1_500 ])
      ])

      run = orchestrator(fake).run("Qual minha meta?").agent_run
      assert_equal 3_000, run.input_tokens
      assert_equal 400, run.output_tokens
      assert_equal 2_000, run.cache_read_tokens
      assert run.cost_estimate.positive?
    end
  end
end
