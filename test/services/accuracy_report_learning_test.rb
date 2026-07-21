require "test_helper"

# U3: acurácia de recompra (escopo por parceiro), recomendações úteis/descartadas
# por vendedor e receita influenciada — com isolamento por equipe.
class AccuracyReportLearningTest < ActiveSupport::TestCase
  setup do
    @n = 0
    @sp_a = Salesperson.create!(external_code: 9701, nickname: "ANA")
    @sp_b = Salesperson.create!(external_code: 9702, nickname: "BRUNO")
    @pa = Partner.create!(external_code: 9801, name: "CLIENTE A")
    @pb = Partner.create!(external_code: 9802, name: "CLIENTE B")
    Wallet.create!(salesperson: @sp_a, partner: @pa, responsibility_type: :owner)
    Wallet.create!(salesperson: @sp_b, partner: @pb, responsibility_type: :owner)

    # Recompra: partner_a (equipe) = 2 confirmadas + 1 perdida + 1 aberta (ignorada);
    # partner_b (fora) = 1 confirmada.
    pred(@pa, :confirmed, exp: 1000, act: 1200) # erro 16,7%
    pred(@pa, :confirmed) # sem valor real → não entra no erro
    pred(@pa, :missed)
    pred(@pa, :open) # aberta: não é "resolvida"
    pred(@pb, :confirmed, exp: 500, act: 400) # erro 25%

    # Recomendações (datas distintas p/ o índice único por vendedor/parceiro/dia).
    @r1 = rec(@sp_a, Date.current, feedback: :useful, status: :accepted)
    @r2 = rec(@sp_a, Date.current - 1, feedback: :useful, status: :done)
    rec(@sp_a, Date.current - 2, feedback: :not_useful, status: :accepted)
    rec(@sp_a, Date.current - 3, status: :discarded)
    @rb = rec(@sp_b, Date.current, feedback: :useful, status: :accepted)

    # Receita influenciada: sp_a 3000 (mês) + 2000 (mês anterior); sp_b 5000 (mês).
    InfluencedRevenue.create!(recommendation: @r1, amount: 3000)
    old = InfluencedRevenue.create!(recommendation: @r2, amount: 2000)
    old.update_column(:created_at, 2.months.ago)
    InfluencedRevenue.create!(recommendation: @rb, amount: 5000)

    @coord = User.create!(email_address: "coord@x.com", password: "secret123", role: :coordenador)
    User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a, manager: @coord)
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
  end

  test "recompra: taxa de confirmação e erro de valor (irrestrito vê tudo)" do
    r = report(@gestor).repurchases
    assert_equal 4, r[:resolved]
    assert_equal 3, r[:confirmed]
    assert_equal 1, r[:missed]
    assert_equal 75.0, r[:confirmed_percent]
    assert_equal 20.8, r[:value_error_percent] # (16,7 + 25,0) / 2, ignorando a sem valor real
  end

  test "recompra: coordenador só avalia parceiros da equipe" do
    r = report(@coord).repurchases
    assert_equal 3, r[:resolved]      # só partner_a: 2 confirmadas + 1 perdida
    assert_equal 66.7, r[:confirmed_percent]
    assert_equal 16.7, r[:value_error_percent] # só a confirmada de A com valor real
  end

  test "recomendações: úteis × não úteis × descartadas por vendedor" do
    result = report(@gestor).recommendations
    assert_equal 5, result[:summary][:total]
    assert_equal 3, result[:summary][:useful]
    assert_equal 75.0, result[:summary][:useful_percent] # 3 úteis / (3 úteis + 1 não útil)

    ana = result[:by_seller].find { |s| s[:name] == "ANA" }
    assert_equal 4, ana[:total]
    assert_equal 2, ana[:useful]
    assert_equal 1, ana[:not_useful]
    assert_equal 1, ana[:discarded]
    assert_equal 66.7, ana[:useful_percent]
    assert_equal 5000.0, ana[:influenced_amount] # 3000 + 2000, acumulado
  end

  test "recomendações: coordenador não vê outra equipe" do
    result = report(@coord).recommendations
    assert_equal %w[ANA], result[:by_seller].map { |s| s[:name] }
    assert_equal 4, result[:summary][:total] # BRUNO fora
  end

  test "receita influenciada: total e mês, escopados" do
    gestor = report(@gestor).influenced_revenue
    assert_equal 10_000.0, gestor[:total]     # 3000 + 2000 + 5000
    assert_equal 8_000.0, gestor[:this_month] # 3000 + 5000 (2000 é de mês anterior)

    coord = report(@coord).influenced_revenue
    assert_equal 5_000.0, coord[:total]       # só sp_a
    assert_equal 3_000.0, coord[:this_month]
  end

  private

  def report(user)
    AccuracyReport.new(AccessPolicy.new(user))
  end

  def pred(partner, status, exp: nil, act: nil)
    @n += 1
    RepurchasePrediction.create!(partner: partner, level: :customer, target_key: "t#{@n}",
                                 status: status, expected_value: exp, actual_value: act,
                                 resolved_at: (status == :open ? nil : Time.current))
  end

  def rec(salesperson, date, feedback: nil, status: :pending)
    Recommendation.create!(salesperson: salesperson, partner: @pa, reference_date: date,
                           feedback: feedback, status: status)
  end
end
