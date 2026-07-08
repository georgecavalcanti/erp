# Interpreta a "Descrição (Tipo de Negociação)" do ERP e deriva os vencimentos.
#
# Exemplos:
#   "V BOLETO - 30 DIAS"    -> offsets [30]        (1 parcela em 30 dias)
#   "V BOLETO - 30/45"      -> offsets [30, 45]    (2 parcelas)
#   "V BOLETO - 30/45/60"   -> offsets [30, 45, 60]
#   "A VISTA - PIX"         -> offsets [0]         (à vista)
#
# first_due_date = negociação + menor offset
# due_date       = negociação + maior offset (liquidação final; base da inadimplência)
class PaymentTermsParser
  Result = Struct.new(:offsets, :first_due_date, :due_date, keyword_init: true)

  CASH_REGEX = /\bA\s*VISTA\b/i

  def self.call(raw, negotiation_date:)
    new(raw, negotiation_date).call
  end

  def initialize(raw, negotiation_date)
    @raw = raw.to_s
    @negotiation_date = negotiation_date
  end

  def call
    offsets = parse_offsets
    first = due = @negotiation_date

    if @negotiation_date && offsets.any?
      first = @negotiation_date + offsets.min
      due   = @negotiation_date + offsets.max
    end

    Result.new(offsets: offsets, first_due_date: first, due_date: due)
  end

  private

  def parse_offsets
    return [0] if @raw.match?(CASH_REGEX)

    nums = @raw.scan(/\d+/).map(&:to_i).select(&:positive?)
    return [0] if nums.empty? # sem prazo reconhecido -> trata como à vista

    nums.uniq.sort
  end
end
