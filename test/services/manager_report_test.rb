require "test_helper"

# Agregações da equipe + o eixo de segurança: o coordenador só enxerga a própria
# equipe; o irrestrito (gestor/admin) vê todos os vendedores com atividade.
class ManagerReportTest < ActiveSupport::TestCase
  setup do
    # sp_a, sp_b = equipe do coordenador; sp_c = fora da equipe.
    @sp_a = Salesperson.create!(external_code: 9101, nickname: "ANA")
    @sp_b = Salesperson.create!(external_code: 9102, nickname: "BRUNO")
    @sp_c = Salesperson.create!(external_code: 9103, nickname: "CARLA")

    # Metas de faturamento do mês corrente.
    Goal.create!(salesperson: @sp_a, period: Date.current, kind: :revenue, amount: 100_000)
    Goal.create!(salesperson: @sp_b, period: Date.current, kind: :revenue, amount: 50_000)
    Goal.create!(salesperson: @sp_c, period: Date.current, kind: :revenue, amount: 100_000)

    # Realizado do mês (venda − devolução), com margem.
    invoice(@sp_a, 9201, 60_000, :sale, margin: 20_000)
    invoice(@sp_a, 9202, 5_000, :return, margin: 5_000) # sp_a líquido 55_000 / margem 15_000
    invoice(@sp_b, 9203, 50_000, :sale, margin: 12_000) # sp_b líquido 50_000
    invoice(@sp_c, 9204, 20_000, :sale, margin: 3_000)  # sp_c líquido 20_000

    # Projeção persistida (última leva) — sp_b propositalmente sem projeção.
    projection(@sp_a, low: 80_000, likely: 90_000, high: 100_000, target: 100_000)
    projection(@sp_c, low: 50_000, likely: 70_000, high: 90_000, target: 100_000)

    # Usuários para o AccessPolicy: coordenador com 2 subordinados; gestor irrestrito.
    @coord = User.create!(email_address: "coord@x.com", password: "secret123", role: :coordenador)
    User.create!(email_address: "a@x.com", password: "secret123", role: :vendedor, salesperson: @sp_a, manager: @coord)
    User.create!(email_address: "b@x.com", password: "secret123", role: :vendedor, salesperson: @sp_b, manager: @coord)
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
  end

  test "coordenador só vê a própria equipe (isolamento)" do
    rows = ManagerReport.new(AccessPolicy.new(@coord)).team

    assert_equal %w[ANA BRUNO], rows.map { |r| r[:name] } # ordenado por realizado desc
    assert_not_includes rows.map { |r| r[:name] }, "CARLA"
  end

  test "linha reconcilia meta, realizado, projeção e status" do
    rows = ManagerReport.new(AccessPolicy.new(@coord)).team.index_by { |r| r[:name] }

    ana = rows["ANA"]
    assert_equal 100_000.0, ana[:target]
    assert_equal 55_000.0, ana[:realized]
    assert_equal 15_000.0, ana[:realized_margin]
    assert_equal 55.0, ana[:attainment_percent]
    assert_equal 90_000.0, ana[:projected_likely]
    assert_equal 80_000.0, ana[:projected_low]
    assert_equal 100_000.0, ana[:projected_high]
    assert_equal 10_000.0, ana[:gap]           # meta − projeção provável
    assert_equal "atencao", ana[:status]        # projeção fura a meta em 10% (< 15%)

    bruno = rows["BRUNO"]
    assert_nil bruno[:projected_likely]         # sem projeção persistida
    assert_equal 0.0, bruno[:gap]               # sem projeção, gap usa o realizado (= meta)
    assert_equal "no_alvo", bruno[:status]      # realizado alcança a meta
  end

  test "irrestrito vê todos os vendedores com atividade e classifica crítico" do
    rows = ManagerReport.new(AccessPolicy.new(@gestor)).team.index_by { |r| r[:name] }

    assert_equal %w[ANA BRUNO CARLA].sort, rows.keys.sort
    assert_equal "critico", rows["CARLA"][:status] # projeção 70k < 85% da meta 100k
  end

  test "totais consolidam meta, realizado e contagem de risco" do
    totals = ManagerReport.new(AccessPolicy.new(@coord)).totals

    assert_equal 2, totals[:count]
    assert_equal 150_000.0, totals[:target]
    assert_equal 105_000.0, totals[:realized]
    assert_equal 90_000.0, totals[:projected_likely] # bruno conta 0
    assert_equal 70.0, totals[:attainment_percent]
    assert_equal 1, totals[:at_risk_count]           # só ANA (atencao)
  end

  test "escopo vazio (fail-closed) não vê ninguém" do
    # Coordenador SEM equipe e sem vendedor próprio → authorized = [] (fail-closed).
    lonely = User.create!(email_address: "solo@x.com", password: "secret123", role: :coordenador)
    assert_equal [], AccessPolicy.new(lonely).authorized_salesperson_ids
    assert_empty ManagerReport.new(AccessPolicy.new(lonely)).team
  end

  test "alertas: coordenador só vê os da sua equipe; irrestrito vê todos" do
    alert_for(@sp_a, "alerta-ana")
    alert_for(@sp_c, "alerta-carla")

    coord_alerts = ManagerReport.new(AccessPolicy.new(@coord)).alerts.map { |a| a[:title] }
    assert_includes coord_alerts, "alerta-ana"
    assert_not_includes coord_alerts, "alerta-carla"

    gestor_alerts = ManagerReport.new(AccessPolicy.new(@gestor)).alerts.map { |a| a[:title] }
    assert_includes gestor_alerts, "alerta-ana"
    assert_includes gestor_alerts, "alerta-carla"
  end

  private

  def invoice(salesperson, uid, value, kind, margin: nil)
    Invoice.create!(external_uid: uid, negotiation_date: Date.current, total_value: value,
                    kind: kind, salesperson: salesperson, margin_value: margin)
  end

  def projection(salesperson, low:, likely:, high:, target:)
    { conservative: low, likely: likely, potential: high }.each do |scenario, value|
      Projection.create!(salesperson: salesperson, reference_date: Date.current, scenario: scenario,
                         value: value, target_value: target, confidence: 72)
    end
  end

  def alert_for(salesperson, title)
    Alert.create!(area: :business, severity: :medium, key: "#{title}-#{salesperson.id}", title: title,
                  entity_type: "Salesperson", entity_id: salesperson.id,
                  first_detected_at: Time.current, last_detected_at: Time.current)
  end
end
