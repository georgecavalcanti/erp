# Calendário de dias úteis com feriados NACIONAIS do Brasil (doc 05.1), sem gem.
# Fixos + Sexta-feira Santa (derivada da Páscoa) + Consciência Negra (nacional
# desde 2024). Carnaval e Corpus Christi são ponto FACULTATIVO (não nacionais) →
# ficam de fora; a gestão pode refinar o calendário depois.
#
# "dia útil" = seg–sex que não é feriado nacional. Base do ritmo/gap do Cockpit.
module BusinessCalendar
  module_function

  FIXED = [ [ 1, 1 ], [ 4, 21 ], [ 5, 1 ], [ 9, 7 ], [ 10, 12 ], [ 11, 2 ], [ 11, 15 ], [ 12, 25 ] ].freeze

  # Feriados nacionais de um ano (Array<Date>).
  def holidays(year)
    dates = FIXED.map { |m, d| Date.new(year, m, d) }
    dates << Date.new(year, 11, 20) if year >= 2024 # Consciência Negra (Lei 14.759/2023)
    dates << good_friday(year)
    dates
  end

  def holiday?(date)
    holidays(date.year).include?(date)
  end

  def business_day?(date)
    !date.saturday? && !date.sunday? && !holiday?(date)
  end

  # Nº de dias úteis num intervalo de datas (inclusivo nas duas pontas).
  def count(range)
    range.sum { |d| business_day?(d) ? 1 : 0 }
  end

  # Estatísticas do mês de `as_of`:
  #   total     = dias úteis do mês
  #   elapsed   = dias úteis de 1º..as_of (HOJE conta como decorrido)
  #   remaining = dias úteis de (as_of+1)..fim do mês (exclui hoje)
  def month_stats(as_of = Date.current)
    month_start = as_of.beginning_of_month
    month_end = as_of.end_of_month
    total = count(month_start..month_end)
    elapsed = count(month_start..as_of)
    { total: total, elapsed: elapsed, remaining: total - elapsed }
  end

  # Domingo de Páscoa (algoritmo de Meeus/Butcher — determinístico, sem tabela).
  def easter(year)
    a = year % 19
    b = year / 100
    c = year % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month = (h + l - 7 * m + 114) / 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    Date.new(year, month, day)
  end

  def good_friday(year)
    easter(year) - 2
  end
end
