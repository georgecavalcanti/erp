require "test_helper"

# Auditoria do agente (Sprint 8): degradação por última resposta válida e
# contabilidade do teto diário de tokens.
class AgentRunTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "last_valid retorna a resposta ok mais recente com output, ignorando erros e schemas inválidos" do
    old_valid = AgentRun.create!(user: @user, kind: :copilot, status: :ok,
                                 output: { "resumo" => "antigo" }, created_at: 2.hours.ago)
    AgentRun.create!(user: @user, kind: :copilot, status: :error, output: nil)
    AgentRun.create!(user: @user, kind: :copilot, status: :invalid_schema, output: { "quebrado" => true })
    AgentRun.create!(user: @user, kind: :cockpit_summary, status: :ok, output: { "resumo" => "outro tipo" })

    assert_equal old_valid, AgentRun.last_valid(user: @user, kind: :copilot)

    newer = AgentRun.create!(user: @user, kind: :copilot, status: :ok, output: { "resumo" => "novo" })
    assert_equal newer, AgentRun.last_valid(user: @user, kind: :copilot)
  end

  test "last_valid é por usuário — não vaza resposta de outro" do
    AgentRun.create!(user: users(:two), kind: :copilot, status: :ok, output: { "resumo" => "do outro" })
    assert_nil AgentRun.last_valid(user: @user, kind: :copilot)
  end

  test "tokens_spent_today soma input+output só do dia e ignora cache read" do
    AgentRun.create!(user: @user, kind: :copilot, status: :ok,
                     input_tokens: 1_000, output_tokens: 200, cache_read_tokens: 50_000)
    AgentRun.create!(user: users(:two), kind: :daily_plan, status: :error,
                     input_tokens: 300, output_tokens: 0)
    AgentRun.create!(user: @user, kind: :copilot, status: :ok,
                     input_tokens: 9_999, output_tokens: 1, created_at: 2.days.ago)

    assert_equal 1_500, AgentRun.tokens_spent_today
  end

  test "cost_estimate usa a tabela de preços e cobra cache read a 0,1x do input" do
    cost = Agent::Config.cost_estimate(model: "claude-haiku-4-5",
                                       input_tokens: 1_000_000, output_tokens: 100_000,
                                       cache_read_tokens: 1_000_000)
    # 1M in × $1 + 100k out × $5 + 1M cache × $0,10 = 1,0 + 0,5 + 0,1
    assert_in_delta 1.6, cost, 0.000001

    assert_nil Agent::Config.cost_estimate(model: "modelo-desconhecido", input_tokens: 1, output_tokens: 1)
  end
end
