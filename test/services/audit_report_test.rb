require "test_helper"

# Agregações da auditoria: gasto do agente por dia/usuário/vendedor, ferramentas e alertas.
class AuditReportTest < ActiveSupport::TestCase
  setup do
    @sp_a = Salesperson.create!(external_code: 9901, nickname: "ANA")
    @sp_b = Salesperson.create!(external_code: 9902, nickname: "BRUNO")
    @u1 = User.create!(email_address: "u1@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a)
    @u2 = User.create!(email_address: "u2@x.com", password: "secret123", role: :vendedor, salesperson: @sp_b)

    # Hoje: 2 execuções ok do u1/sp_a. Dias atrás: 1 execução com erro do u2/sp_b.
    make_run(@u1, @sp_a, kind: :copilot, status: :ok, cost: 0.10, input: 1000, output: 500, cache_write: 200,
        at: Time.current, tools: [ tool("priorizar_carteira", 20), tool("consultar_resultado_vendedor", 40) ])
    make_run(@u1, @sp_a, kind: :daily_plan, status: :ok, cost: 0.05, input: 400, output: 200, cache_write: 0,
        at: Time.current, tools: [ tool("priorizar_carteira", 30) ])
    make_run(@u2, @sp_b, kind: :copilot, status: :error, cost: 0.02, input: 100, output: 0, cache_write: 0,
        at: Time.current - 3.days, tools: [ tool("consultar_resultado_vendedor", 10, ok: false) ])
  end

  test "summary: execuções, erros e gasto de hoje" do
    s = AuditReport.new.summary
    assert_equal 3, s[:total_runs]
    assert_equal 1, s[:error_runs]
    assert_equal 0.15, s[:today_cost] # só as 2 de hoje (0.10 + 0.05)
    assert_equal 20.0, s[:monthly_budget]
    assert_equal 1.0, s[:per_seller_daily_cap]
  end

  test "por dia: um bucket por dia de negócio" do
    days = AuditReport.new.by_day
    assert_equal 2, days.size
    assert_equal 0.17, days.sum { |d| d[:cost] }.round(4)
    assert_equal 1, days.sum { |d| d[:errors] }
  end

  test "por usuário: ordenado por custo" do
    users = AuditReport.new.by_user
    assert_equal "u1@x.com", users.first[:user]
    assert_equal 0.15, users.first[:cost]
    assert_equal 2, users.first[:calls]
  end

  test "por vendedor: custo da janela e de hoje × teto" do
    ana = AuditReport.new.by_seller.find { |s| s[:salesperson] == "ANA" }
    bruno = AuditReport.new.by_seller.find { |s| s[:salesperson] == "BRUNO" }
    assert_equal 0.15, ana[:cost]
    assert_equal 0.15, ana[:today_cost]
    assert_equal 0.0, bruno[:today_cost] # execução de BRUNO foi 3 dias atrás
  end

  test "ferramentas mais chamadas: contagem, média e falhas" do
    tools = AuditReport.new.top_tools.index_by { |t| t[:name] }
    assert_equal 2, tools["priorizar_carteira"][:calls]
    assert_equal 25, tools["priorizar_carteira"][:avg_ms] # (20 + 30) / 2
    assert_equal 2, tools["consultar_resultado_vendedor"][:calls]
    assert_equal 1, tools["consultar_resultado_vendedor"][:failures]
  end

  test "execuções recentes trazem ferramentas e status" do
    recent = AuditReport.new.recent_runs
    assert_equal 3, recent.size
    top = recent.first
    assert_includes top[:tools], "priorizar_carteira"
    assert_equal "ok", top[:status]
  end

  test "alertas abertos agrupados por área" do
    Alert.create!(area: :ia, severity: :high, key: "ia-1", title: "Teto", first_detected_at: Time.current, last_detected_at: Time.current)
    Alert.create!(area: :business, severity: :medium, key: "biz-1", title: "Meta ausente", first_detected_at: Time.current, last_detected_at: Time.current)
    Alert.create!(area: :business, severity: :low, key: "biz-2", title: "Resolvido", first_detected_at: Time.current, last_detected_at: Time.current, resolved_at: Time.current)

    result = AuditReport.new.alerts
    by_area = result[:by_area].index_by { |a| a[:area] }
    assert_equal 1, by_area["ia"][:count]
    assert_equal 1, by_area["business"][:count] # o resolvido não conta
    assert_equal 2, result[:recent].size
  end

  private

  def make_run(user, salesperson, kind:, status:, cost:, input:, output:, cache_write:, at:, tools:)
    AgentRun.create!(user: user, salesperson: salesperson, kind: kind, status: status, model: "claude-haiku-4-5",
                     cost_estimate: cost, input_tokens: input, output_tokens: output, cache_write_tokens: cache_write,
                     cache_read_tokens: 0, latency_ms: 500, tools_called: tools, created_at: at)
  end

  def tool(name, duration, ok: true)
    { "name" => name, "ok" => ok, "params" => {}, "duration_ms" => duration }
  end
end
