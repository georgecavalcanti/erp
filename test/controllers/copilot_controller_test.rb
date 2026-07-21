require "test_helper"

# Copiloto (Sprint 8): página, escopo por perfil e o SSE de pergunta. A lógica
# do agente é testada em test/services/agent/orchestrator_test.rb — aqui o foco
# é o transporte (Inertia + SSE) e a degradação sem IA (MVP 13).
class CopilotControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sp = Salesperson.create!(external_code: 97_001, nickname: "VEND.COP")
    @cliente = Partner.create!(external_code: 97_101, name: "Cliente Cop")
    Wallet.create!(salesperson: @sp, partner: @cliente, starts_on: 1.year.ago)
    @vend = User.create!(email_address: "cop@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
  end

  test "vendedor abre o copiloto com sugestões e sem IA configurada" do
    sign_in_as(@vend)
    get copilot_path

    assert_inertia_component "Copilot"
    assert_equal @sp.nickname, inertia.props[:salesperson][:name]
    assert_equal 5, inertia.props[:suggestions].size
    assert_equal false, inertia.props[:agentEnabled] # sem ANTHROPIC_API_KEY no test
  end

  test "última resposta válida aparece para degradação (MVP 13)" do
    AgentRun.create!(user: @vend, kind: :copilot, status: :ok, salesperson: @sp,
                     output: { "resumo" => "Plano de ontem: 3 clientes", "recomendacoes" => [] })
    sign_in_as(@vend)
    get copilot_path

    assert_equal "Plano de ontem: 3 clientes", inertia.props[:lastResponse][:resumo]
    assert inertia.props[:lastResponse][:generated_at].present?
  end

  test "perguntar responde SSE e degrada sem IA — a consulta não quebra (MVP 13)" do
    sign_in_as(@vend)
    post copilot_ask_path, params: { question: "Monte meu plano" }, as: :json

    assert_response :success
    assert_equal "text/event-stream", response.headers["Content-Type"]
    assert_match(/event: result/, response.body)
    payload = JSON.parse(response.body[/data: (.+)/, 1])
    assert payload["degraded"]
    assert_match(/IA não configurada/, payload["aviso"])
  end

  test "pergunta vazia devolve evento de erro" do
    sign_in_as(@vend)
    post copilot_ask_path, params: { question: "" }, as: :json

    assert_match(/event: error/, response.body)
  end

  test "diretoria não acessa o copiloto (matriz doc 07)" do
    diretoria = User.create!(email_address: "dir@x.com", password: "secret123", role: :diretoria)
    sign_in_as(diretoria)

    get copilot_path
    assert_redirected_to root_path
  end

  test "vendedor não troca o contexto para vendedor de outra carteira" do
    outro = Salesperson.create!(external_code: 97_002, nickname: "OUTRO.COP")
    sign_in_as(@vend)

    get copilot_path, params: { salesperson_id: outro.id }
    # Pedir outro vendedor não escapa do escopo: continua no próprio.
    assert_equal @sp.id, inertia.props[:salesperson][:id]
    assert_nil inertia.props[:salespeople], "vendedor não vê o seletor de vendedores"
  end
end
