module Sankhya
  # Configuração lida de variáveis de ambiente (Railway em produção; shell/.env
  # em dev). Segredos NUNCA no repositório.
  #
  #   SANKHYA_CLIENT_ID      # Portal do Desenvolvedor
  #   SANKHYA_CLIENT_SECRET  # Portal do Desenvolvedor
  #   SANKHYA_X_TOKEN        # App Token — tela "Configurações Gateway" do Sankhya Om
  #   SANKHYA_BASE_URL       # default sandbox; produção = https://api.sankhya.com.br
  module Config
    DEFAULT_BASE_URL = "https://api.sandbox.sankhya.com.br".freeze

    def self.client_id     = ENV["SANKHYA_CLIENT_ID"]
    def self.client_secret = ENV["SANKHYA_CLIENT_SECRET"]
    def self.x_token       = ENV["SANKHYA_X_TOKEN"]
    def self.base_url      = ENV["SANKHYA_BASE_URL"].presence || DEFAULT_BASE_URL

    # Timeouts (s). O Gateway pode levar até ~2 min processando uma consulta.
    def self.open_timeout = Integer(ENV.fetch("SANKHYA_OPEN_TIMEOUT", 10))
    def self.read_timeout = Integer(ENV.fetch("SANKHYA_READ_TIMEOUT", 130))

    # Margem (s) subtraída do expires_in ao cachear o token, para renovar antes
    # de expirar de fato (não há refresh token — reautentica do zero).
    def self.token_safety_margin = 60

    def self.sandbox? = base_url.to_s.include?("sandbox")

    # Falha cedo com mensagem clara se faltar segredo — melhor que um 401 obscuro.
    def self.validate!
      missing = {
        "SANKHYA_CLIENT_ID" => client_id,
        "SANKHYA_CLIENT_SECRET" => client_secret,
        "SANKHYA_X_TOKEN" => x_token
      }.select { |_, v| v.to_s.strip.empty? }.keys

      return true if missing.empty?

      raise Sankhya::AuthError, "Faltam variáveis de ambiente: #{missing.join(', ')}"
    end
  end
end
