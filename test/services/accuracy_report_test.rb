require "test_helper"

# Acurácia de projeção: snapshot de INÍCIO do mês (não o mais recente) × realizado
# real, só meses fechados, escopado por equipe.
class AccuracyReportTest < ActiveSupport::TestCase
  # Fixa o "hoje" em julho/2026 → junho e maio são meses fechados; julho não entra.
  AS_OF = Date.new(2026, 7, 20)

  setup do
    @sp_a = Salesperson.create!(external_code: 9501, nickname: "ANA")
    @sp_b = Salesperson.create!(external_code: 9502, nickname: "BRUNO")

    # sp_a / junho: snapshot inicial provável 100k (faixa 80–120); um snapshot MAIS
    # NOVO no mesmo mês (provável 90k) NÃO deve ser o avaliado.
    proj(@sp_a, Date.new(2026, 6, 2), cons: 80_000, likely: 100_000, pot: 120_000, target: 100_000)
    proj(@sp_a, Date.new(2026, 6, 20), cons: 85_000, likely: 90_000, pot: 95_000, target: 100_000)
    # Realizado junho de sp_a = 115k − 5k = 110k → dentro da faixa; erro |100−110|/110 = 9,1%.
    invoice(@sp_a, 9601, 115_000, :sale, Date.new(2026, 6, 10))
    invoice(@sp_a, 9602, 5_000, :return, Date.new(2026, 6, 12))

    # sp_b / maio: provável 100k (faixa 50–110); realizado 200k → fora da faixa; erro 50%.
    proj(@sp_b, Date.new(2026, 5, 5), cons: 50_000, likely: 100_000, pot: 110_000, target: 100_000)
    invoice(@sp_b, 9603, 200_000, :sale, Date.new(2026, 5, 15))

    # Projeção do mês CORRENTE (julho) — não pode ser avaliada (mês aberto).
    proj(@sp_a, Date.new(2026, 7, 1), cons: 900_000, likely: 999_000, pot: 999_000, target: 100_000)

    @coord = User.create!(email_address: "coord@x.com", password: "secret123", role: :coordenador)
    User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a, manager: @coord)
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
  end

  test "avalia o snapshot de início do mês, não o mais recente" do
    result = report(@gestor).projections
    ana = result[:by_seller].find { |s| s[:name] == "ANA" }

    assert_equal "2026-06", ana[:last][:month]
    assert_equal 100_000.0, ana[:last][:predicted] # snapshot de 02/06, não o de 20/06 (90k)
    assert_equal 110_000.0, ana[:last][:realized]
    assert ana[:last][:hit]
    assert_equal 9.1, ana[:mean_abs_error_percent]
    assert_equal 100.0, ana[:within_band_percent]
  end

  test "realizado fora da faixa não conta como acerto" do
    bruno = report(@gestor).projections[:by_seller].find { |s| s[:name] == "BRUNO" }

    assert_not bruno[:last][:hit]
    assert_equal 0.0, bruno[:within_band_percent]
    assert_equal 50.0, bruno[:mean_abs_error_percent]
  end

  test "resumo consolida faixa e erro; ignora o mês aberto" do
    summary = report(@gestor).projections[:summary]

    assert_equal 2, summary[:pairs]              # junho(sp_a) + maio(sp_b); julho fora
    assert_equal 2, summary[:months_evaluated]
    assert_equal 50.0, summary[:within_band_percent] # 1 de 2 dentro da faixa
    assert_equal 29.6, summary[:mean_abs_error_percent] # (9,1 + 50,0) / 2
  end

  test "coordenador só avalia a própria equipe" do
    result = report(@coord).projections

    names = result[:by_seller].map { |s| s[:name] }
    assert_equal ["ANA"], names # BRUNO fora da equipe
    assert_equal 1, result[:summary][:pairs]
  end

  test "sem meses fechados devolve resultado vazio" do
    sp = Salesperson.create!(external_code: 9509, nickname: "SEM")
    proj(sp, Date.new(2026, 7, 1), cons: 1, likely: 2, pot: 3, target: 2) # só mês aberto
    only = User.create!(email_address: "c@x.com", password: "secret123", role: :coordenador)
    User.create!(email_address: "sem@x.com", password: "secret123", role: :vendedor, salesperson: sp, manager: only)

    result = report(only).projections
    assert_equal 0, result[:summary][:pairs]
    assert_empty result[:by_seller]
  end

  private

  def report(user)
    AccuracyReport.new(AccessPolicy.new(user), as_of: AS_OF)
  end

  def proj(salesperson, date, cons:, likely:, pot:, target:)
    { conservative: cons, likely: likely, potential: pot }.each do |scenario, value|
      Projection.create!(salesperson: salesperson, reference_date: date, scenario: scenario,
                         value: value, target_value: target, confidence: 70)
    end
  end

  def invoice(salesperson, uid, value, kind, date)
    Invoice.create!(external_uid: uid, negotiation_date: date, total_value: value, kind: kind, salesperson: salesperson)
  end
end
