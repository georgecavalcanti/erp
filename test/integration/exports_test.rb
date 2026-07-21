require "test_helper"

# Exportações controladas e registradas (doc 09): só gestor+ exporta, e cada
# exportação vira um ExportLog.
class ExportsTest < ActionDispatch::IntegrationTest
  setup do
    @sp = Salesperson.create!(external_code: 9950, nickname: "ANA")
    Goal.create!(salesperson: @sp, period: Date.current, kind: :revenue, amount: 100_000)
    Invoice.create!(external_uid: 9951, negotiation_date: Date.current, total_value: 40_000, kind: :sale, salesperson: @sp)

    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
    @coord = User.create!(email_address: "c@x.com", password: "secret123", role: :coordenador)
    sp_v = Salesperson.create!(external_code: 9959, nickname: "VITOR")
    @vendedor = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: sp_v)
  end

  test "gestor exporta CSV da equipe e registra o export" do
    sign_in_as(@gestor)
    assert_difference "ExportLog.count", 1 do
      get manager_export_path
    end
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Vendedor"
    assert_includes response.body, "ANA"

    log = ExportLog.recent.first
    assert_equal "equipe", log.kind
    assert_equal @gestor, log.user
    assert_equal 1, log.row_count
    assert_equal Date.current.strftime("%Y-%m"), log.filters["month"]
  end

  test "coordenador não exporta a equipe (exportação é gestor+)" do
    sign_in_as(@coord)
    assert_no_difference "ExportLog.count" do
      get manager_export_path
    end
    assert_redirected_to root_path
  end

  test "vendedor não acessa a exportação da equipe" do
    sign_in_as(@vendedor)
    assert_no_difference "ExportLog.count" do
      get manager_export_path
    end
    assert_redirected_to root_path
  end

  test "gestor exporta CSV de custo do agente e registra" do
    AgentRun.create!(user: @gestor, salesperson: @sp, kind: :copilot, status: :ok, model: "claude-haiku-4-5",
                     cost_estimate: 0.05, input_tokens: 100, output_tokens: 50, tools_called: [])
    sign_in_as(@gestor)
    assert_difference "ExportLog.count", 1 do
      get audit_export_path
    end
    assert_response :success
    assert_includes response.body, "ANA"
    assert_equal "custo_agente", ExportLog.recent.first.kind
  end

  test "coordenador não acessa a exportação de auditoria" do
    sign_in_as(@coord)
    assert_no_difference "ExportLog.count" do
      get audit_export_path
    end
    assert_redirected_to root_path
  end
end
