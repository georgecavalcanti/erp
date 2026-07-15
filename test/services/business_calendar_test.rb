require "test_helper"

class BusinessCalendarTest < ActiveSupport::TestCase
  test "feriados nacionais fixos e Consciência Negra (2024+)" do
    assert BusinessCalendar.holiday?(Date.new(2026, 12, 25)) # Natal
    assert BusinessCalendar.holiday?(Date.new(2026, 9, 7))   # Independência
    assert BusinessCalendar.holiday?(Date.new(2026, 11, 20)) # Consciência Negra
    assert_not BusinessCalendar.holiday?(Date.new(2023, 11, 20)) # antes de 2024 não era nacional
  end

  test "feriado móvel: Sexta-feira Santa derivada da Páscoa" do
    assert_equal Date.new(2026, 4, 5), BusinessCalendar.easter(2026) # domingo de Páscoa
    gf = BusinessCalendar.good_friday(2026)
    assert_equal Date.new(2026, 4, 3), gf
    assert gf.friday?
    assert_not BusinessCalendar.business_day?(gf)
  end

  test "business_day? ignora fins de semana e feriados" do
    assert BusinessCalendar.business_day?(Date.new(2026, 7, 15))     # quarta comum
    assert_not BusinessCalendar.business_day?(Date.new(2026, 7, 18)) # sábado
    assert_not BusinessCalendar.business_day?(Date.new(2026, 7, 19)) # domingo
    assert_not BusinessCalendar.business_day?(Date.new(2026, 1, 1))  # feriado
  end

  test "count: dias úteis de um intervalo conhecido" do
    # 01/07/2026 (qua) a 07/07/2026 (ter): qua,qui,sex,[sáb,dom],seg,ter = 5 úteis
    assert_equal 5, BusinessCalendar.count(Date.new(2026, 7, 1)..Date.new(2026, 7, 7))
  end

  test "month_stats: elapsed + remaining = total; hoje conta como decorrido" do
    as_of = Date.new(2026, 7, 15) # quarta, dia útil
    s = BusinessCalendar.month_stats(as_of)

    assert_operator s[:total], :>=, 20
    assert_equal s[:total], s[:elapsed] + s[:remaining]
    # 15/07 é dia útil e entra em elapsed; o dia útil seguinte fica em remaining.
    assert_equal s[:elapsed], BusinessCalendar.count(Date.new(2026, 7, 1)..as_of)
    assert_operator s[:remaining], :>, 0
  end
end
