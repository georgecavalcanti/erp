require "test_helper"

class ProjectionRecalcJobTest < ActiveJob::TestCase
  test "persiste projeções só dos vendedores com meta no mês (3 cenários cada)" do
    com_meta = Salesperson.create!(external_code: 2001, nickname: "COM")
    Goal.create!(salesperson: com_meta, period: Date.current, kind: :revenue, amount: 10_000)
    sem_meta = Salesperson.create!(external_code: 2002, nickname: "SEM")

    persisted = ProjectionRecalcJob.new.perform

    assert_equal 1, persisted
    assert_equal 3, Projection.where(salesperson: com_meta).count
    assert_equal 0, Projection.where(salesperson: sem_meta).count
  end

  test "salesperson_id específico projeta só aquele vendedor" do
    a = Salesperson.create!(external_code: 2003, nickname: "A")
    Salesperson.create!(external_code: 2004, nickname: "B")

    ProjectionRecalcJob.new.perform(a.id)

    assert_equal 3, Projection.count
    assert_equal 3, Projection.where(salesperson: a).count
  end
end
