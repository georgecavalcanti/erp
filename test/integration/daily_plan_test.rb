require "test_helper"

# Plano do Dia (Sprint 7): escopo por carteira, ações sobre recomendações e
# registro de resultado (receita influenciada). Isolamento entre vendedores.
class DailyPlanTest < ActionDispatch::IntegrationTest
  setup do
    @sp_a = Salesperson.create!(external_code: 10_001, nickname: "VEND.A")
    @sp_b = Salesperson.create!(external_code: 10_002, nickname: "VEND.B")
    @pa = Partner.create!(external_code: 10_101, name: "CLIENTE A", active: true)
    @pb = Partner.create!(external_code: 10_102, name: "CLIENTE B", active: true)
    Wallet.create!(salesperson: @sp_a, partner: @pa)
    Wallet.create!(salesperson: @sp_b, partner: @pb)
    Invoice.create!(external_uid: 10_201, negotiation_date: Date.current - 20, total_value: 5_000,
                    kind: :sale, confirmed: true, partner: @pa, salesperson: @sp_a, margin_value: 1_500)
    Invoice.create!(external_uid: 10_202, negotiation_date: Date.current - 20, total_value: 5_000,
                    kind: :sale, confirmed: true, partner: @pb, salesperson: @sp_b, margin_value: 1_500)
    @vend_a = User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a)
    @vend_b = User.create!(email_address: "b@x.com", password: "secret123", role: :vendedor, salesperson: @sp_b)
  end

  test "vendedor vê só o próprio plano (gera sob demanda)" do
    sign_in_as(@vend_a)
    get daily_plan_path

    assert_inertia_component "DailyPlan"
    assert_equal @sp_a.id, inertia.props[:salesperson][:id]
    partner_ids = inertia.props[:recommendations].map { |r| r[:partner_id] }
    assert_includes partner_ids, @pa.id
    assert_not_includes partner_ids, @pb.id # nunca o cliente de B
  end

  test "concluir uma recomendação muda o status" do
    Engines::Prioritization.new(@sp_a).persist!
    rec = Recommendation.where(salesperson: @sp_a, partner: @pa).first
    sign_in_as(@vend_a)

    patch recommendation_path(rec), params: { event: "concluir" }
    assert_predicate rec.reload, :status_done?
  end

  test "registrar resultado cria receita influenciada + atividade e conclui" do
    Engines::Prioritization.new(@sp_a).persist!
    rec = Recommendation.where(salesperson: @sp_a, partner: @pa).first
    sign_in_as(@vend_a)

    assert_difference [ "InfluencedRevenue.count", "Activity.count" ], 1 do
      post recommendation_result_path(rec), params: { amount: "1234.50", notes: "Fechou pedido" }
    end
    assert_predicate rec.reload, :status_done?
    assert_in_delta 1234.50, rec.influenced_revenues.sum(:amount), 0.01
    a = Activity.last
    assert a.kind_result?
    assert_equal rec.id, a.recommendation_id
  end

  test "registrar resultado NÃO vincula nota de outro cliente (escopo)" do
    Engines::Prioritization.new(@sp_a).persist!
    rec = Recommendation.where(salesperson: @sp_a, partner: @pa).first
    sign_in_as(@vend_a)

    assert_no_difference "InfluencedRevenue.count" do
      # 10202 é nota do CLIENTE B — não pode vincular à recomendação do cliente A
      post recommendation_result_path(rec), params: { amount: "100", invoice_uid: "10202" }
    end
    assert_match(/não encontrada para este cliente/i, flash[:alert])
  end

  test "registrar resultado rejeita valor inválido e não duplica" do
    Engines::Prioritization.new(@sp_a).persist!
    rec = Recommendation.where(salesperson: @sp_a, partner: @pa).first
    sign_in_as(@vend_a)

    assert_no_difference "InfluencedRevenue.count" do
      post recommendation_result_path(rec), params: { amount: "0", notes: "x" } # valor inválido
    end
    # 1º registro válido
    post recommendation_result_path(rec), params: { amount: "500", notes: "ok" }
    # 2º registro (double submit) é rejeitado
    assert_no_difference "InfluencedRevenue.count" do
      post recommendation_result_path(rec), params: { amount: "500", notes: "de novo" }
    end
    assert_equal 1, rec.reload.influenced_revenues.count
  end

  test "vendedor A NÃO age em recomendação de B (isolamento)" do
    Engines::Prioritization.new(@sp_b).persist!
    rec_b = Recommendation.where(salesperson: @sp_b).first
    sign_in_as(@vend_a)

    patch recommendation_path(rec_b), params: { event: "concluir" }
    assert_match(/fora do seu escopo/i, flash[:alert])
    assert_not_predicate rec_b.reload, :status_done?
  end
end
