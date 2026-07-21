require "test_helper"

# Guardas de performance da Sprint 9: a agregação da equipe é set-based (não faz
# N+1 por vendedor) e a acurácia de mês fechado é cacheada por escopo.
class DashboardPerformanceTest < ActiveSupport::TestCase
  AS_OF = Date.new(2026, 7, 20)

  setup do
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
    @seq = 0
  end

  test "agregação da equipe é set-based (nº de queries constante)" do
    seed_sellers(3)
    q_small = count_queries { run_manager }
    seed_sellers(9) # agora 12 vendedores
    q_large = count_queries { run_manager }

    assert_operator q_small, :>, 0
    assert_equal q_small, q_large, "o nº de queries não pode crescer com o nº de vendedores (N+1)"
  end

  test "acurácia de mês fechado vem do cache na 2ª chamada" do
    store = ActiveSupport::Cache::MemoryStore.new
    seed_closed_month_accuracy

    first = accuracy(store).projections
    assert_operator first[:summary][:pairs], :>, 0

    q_second = count_queries { accuracy(store).projections }
    assert_equal 0, q_second, "a 2ª chamada (mesmo escopo/mês) deve vir do cache"
    assert_equal first, accuracy(store).projections
  end

  test "cache da acurácia é isolado por escopo" do
    store = ActiveSupport::Cache::MemoryStore.new
    seed_closed_month_accuracy

    accuracy(store).projections # popula o cache do escopo irrestrito (gestor)

    # Coordenador sem equipe: escopo vazio → resultado próprio (não o do gestor).
    lonely = User.create!(email_address: "c@x.com", password: "secret123", role: :coordenador)
    empty = AccuracyReport.new(AccessPolicy.new(lonely), as_of: AS_OF, cache: store).projections
    assert_equal 0, empty[:summary][:pairs]
  end

  private

  def run_manager
    report = ManagerReport.new(AccessPolicy.new(@gestor), as_of: AS_OF)
    report.team
    report.totals
    report.alerts
  end

  def accuracy(store)
    AccuracyReport.new(AccessPolicy.new(@gestor), as_of: AS_OF, cache: store)
  end

  def seed_sellers(count)
    count.times do
      @seq += 1
      sp = Salesperson.create!(external_code: 40_000 + @seq, nickname: "V#{@seq}")
      Goal.create!(salesperson: sp, period: AS_OF, kind: :revenue, amount: 100_000)
      Invoice.create!(external_uid: 40_000 + @seq, negotiation_date: AS_OF, total_value: 50_000, kind: :sale, salesperson: sp)
      %i[conservative likely potential].each_with_index do |scenario, i|
        Projection.create!(salesperson: sp, reference_date: AS_OF, scenario: scenario,
                           value: 80_000 + i * 10_000, target_value: 100_000, confidence: 70)
      end
    end
  end

  def seed_closed_month_accuracy
    sp = Salesperson.create!(external_code: 41_000, nickname: "ANA")
    %i[conservative likely potential].each_with_index do |scenario, i|
      Projection.create!(salesperson: sp, reference_date: Date.new(2026, 6, 2), scenario: scenario,
                         value: 80_000 + i * 20_000, target_value: 100_000, confidence: 70)
    end
    Invoice.create!(external_uid: 41_000, negotiation_date: Date.new(2026, 6, 10), total_value: 110_000, kind: :sale, salesperson: sp)
  end

  def count_queries
    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      queries += 1 unless payload[:name] == "SCHEMA" || sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
