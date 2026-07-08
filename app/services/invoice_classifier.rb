# Classifica a nota como venda ou devolução a partir das descrições do ERP.
#
# Na amostra atual todas são "VENDA NF-E PRIVADO", mas devoluções chegam com
# "DEVOLUÇÃO ..." no Tipo de Operação (e/ou Natureza). A regra fica centralizada
# e configurável aqui para evoluir sem tocar no importador.
class InvoiceClassifier
  RETURN_MARKERS = %w[DEVOL].freeze # cobre DEVOLUÇÃO / DEVOLUCAO

  def self.kind_for(operation_type_desc:, nature_desc: nil)
    haystack = "#{operation_type_desc} #{nature_desc}".upcase
    RETURN_MARKERS.any? { |marker| haystack.include?(marker) } ? :return : :sale
  end
end
