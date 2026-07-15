require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup { @sp = Salesperson.create!(external_code: 6001, nickname: "S") }

  test "normaliza period para o 1º dia do mês" do
    goal = Goal.create!(salesperson: @sp, period: Date.new(2026, 7, 15), kind: :revenue, amount: 1000)

    assert_equal Date.new(2026, 7, 1), goal.period
  end

  test "uma meta por vendedor/período/tipo (mesmo mês em dias diferentes colide)" do
    Goal.create!(salesperson: @sp, period: Date.new(2026, 7, 1), kind: :revenue, amount: 1000)
    dup = Goal.new(salesperson: @sp, period: Date.new(2026, 7, 20), kind: :revenue, amount: 2000)

    assert_not dup.valid?
    assert dup.errors[:kind].any?
  end

  test "tipos diferentes convivem no mesmo mês" do
    Goal.create!(salesperson: @sp, period: Date.new(2026, 7, 1), kind: :revenue, amount: 1000)
    margin = Goal.new(salesperson: @sp, period: Date.new(2026, 7, 1), kind: :margin, min_margin_percent: 25)

    assert margin.valid?
  end

  test "amount negativo é inválido" do
    goal = Goal.new(salesperson: @sp, period: Date.new(2026, 7, 1), kind: :revenue, amount: -1)

    assert_not goal.valid?
  end
end
