require "test_helper"

# Abordagens do Plano do Dia geradas pelo agente (Sprint 8). A redação em si é
# testada no orchestrator_test (abordagens escopadas); aqui, o fluxo da ação e a
# degradação sem IA.
class DailyPlanAbordagensTest < ActionDispatch::IntegrationTest
  setup do
    @sp = Salesperson.create!(external_code: 98_001, nickname: "VEND.AB")
    @cliente = Partner.create!(external_code: 98_101, name: "Cliente Abord")
    Wallet.create!(salesperson: @sp, partner: @cliente, starts_on: 1.year.ago)
    @vend = User.create!(email_address: "ab@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
  end

  test "plano do dia serializa a abordagem no card" do
    Recommendation.create!(salesperson: @sp, partner: @cliente, reference_date: Date.current,
                           status: :pending, approach: "Abra citando a recompra atrasada.")
    sign_in_as(@vend)
    get daily_plan_path

    card = inertia.props[:recommendations].find { |r| r[:partner_id] == @cliente.id }
    assert_equal "Abra citando a recompra atrasada.", card[:approach]
    assert_equal false, inertia.props[:agentEnabled]
  end

  test "gerar abordagens sem IA degrada com aviso (MVP 13)" do
    Recommendation.create!(salesperson: @sp, partner: @cliente, reference_date: Date.current, status: :pending)
    sign_in_as(@vend)
    post daily_plan_abordagens_path

    assert_redirected_to daily_plan_path(salesperson_id: @sp.id)
    assert_match(/IA não configurada/, flash[:alert])
  end

  test "sem cards pendentes sem abordagem, avisa que nada há a gerar" do
    Recommendation.create!(salesperson: @sp, partner: @cliente, reference_date: Date.current,
                           status: :pending, approach: "já tem")
    sign_in_as(@vend)
    post daily_plan_abordagens_path

    assert_match(/já têm abordagem/, flash[:notice])
  end
end
