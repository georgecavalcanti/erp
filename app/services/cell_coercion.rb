# Conversores de célula compartilhados entre os importadores de planilha.
module CellCoercion
  private

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.strip.gsub(/\s+/, " ")
  end

  def to_integer(value)
    return nil if value.nil?

    case value
    when Integer then value
    when Float then value.to_i
    when String
      s = value.strip
      s.match?(/\A-?\d/) ? s.to_i : nil
    else value.to_i
    end
  end

  def to_decimal(value)
    return BigDecimal("0") if value.nil?

    case value
    when Numeric then BigDecimal(value.to_s)
    when String
      s = value.strip.gsub(/[^\d,.-]/, "")
      return BigDecimal("0") if s.empty?

      # formato brasileiro "1.234,56" -> "1234.56"
      s = s.delete(".").tr(",", ".") if s.count(",") == 1 && (s.rindex(",") || -1) > (s.rindex(".") || -1)
      BigDecimal(s)
    else BigDecimal("0")
    end
  rescue ArgumentError
    BigDecimal("0")
  end

  def to_date(value)
    return nil if value.nil?

    case value
    when Date then value
    when DateTime, Time then value.to_date
    when Numeric then Date.new(1899, 12, 30) + value.to_i # serial Excel
    when String
      s = value.strip
      return nil if s.empty?

      if (m = s.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z}))
        Date.new(m[3].to_i, m[2].to_i, m[1].to_i)
      else
        Date.parse(s) rescue nil
      end
    end
  end

  def to_bool_sim(value)
    normalize(value) == "sim"
  end
end
