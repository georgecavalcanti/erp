# Namespace da integração com a API do Sankhya (API Gateway / OAuth 2.0).
#
# A integração é apenas uma NOVA FONTE que alimenta os MESMOS modelos dos
# importadores de planilha (Invoice, PendingOrder, OverdueTitle, Delinquency,
# Partner, Salesperson, Company). Nada nas telas ou na camada Analytics muda —
# só a origem dos dados. O Sankhya é a fonte da verdade.
module Sankhya
  # Erro base; os demais herdam para permitir rescue seletivo.
  class Error < StandardError; end

  # Falha ao obter/renovar o token OAuth (credenciais, X-Token, HTTP na auth).
  class AuthError < Error; end

  # Falha de transporte/HTTP no Gateway (timeout, 5xx, corpo não-JSON).
  class RequestError < Error; end

  # A query rodou mas o Gateway devolveu status de erro (status != "1").
  class QueryError < Error; end

  # Resultado truncado pelo teto de linhas do servidor (burstLimit=true):
  # sinal de que a consulta precisa ser paginada.
  class BurstLimitError < Error; end
end
