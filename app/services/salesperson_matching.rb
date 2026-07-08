# Casa um rótulo de vendedor da planilha (ex.: "ANA CAROLINA", "VITOR") com um
# Salesperson existente (apelido tipo "ANA.CAROLINA", "VITOR.POROCA"), tolerante
# a acentos, espaços e pontos. Requer @salespeople (Array<Salesperson>).
module SalespersonMatching
  def load_salespeople
    @salespeople = Salesperson.all.to_a
  end

  def match_salesperson(label)
    key = squish(label)
    return nil if key.empty?

    # 1) igualdade normalizada completa ("ANA CAROLINA" == "ANA.CAROLINA")
    exact = @salespeople.find { |s| squish(s.nickname) == key }
    return exact if exact

    # 2) primeiro token do apelido == rótulo (desambigua "VITOR" x "VITORIA")
    by_first = @salespeople.select { |s| squish(s.nickname.split(/[.\s]+/).first) == key }
    return by_first.first if by_first.size == 1

    # 3) prefixo único
    by_prefix = @salespeople.select { |s| squish(s.nickname).start_with?(key) }
    by_prefix.size == 1 ? by_prefix.first : nil
  end

  def squish(value)
    I18n.transliterate(value.to_s).upcase.gsub(/[^A-Z0-9]/, "")
  end
end
