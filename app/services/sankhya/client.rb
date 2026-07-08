require "net/http"
require "json"
require "uri"

module Sankhya
  # Cliente HTTP da API Gateway do Sankhya.
  #
  #   client = Sankhya::Client.new
  #   rows = client.execute_query("SELECT CODEMP, NOMEFANTASIA FROM TGFEMP")
  #   # => [{ "CODEMP" => 1, "NOMEFANTASIA" => "..." }, ...]
  #
  # Responsabilidades:
  #   * autenticar (OAuth 2.0 Client Credentials + header X-Token);
  #   * cachear o token (validade ~1h, sem refresh -> reautentica sozinho);
  #   * rodar SQL somente-leitura via DbExplorerSP.executeQuery (módulo mge);
  #   * devolver cada linha já como Hash (nome da coluna -> valor), zipando
  #     os `rows` posicionais com o `fieldsMetadata`.
  class Client
    GATEWAY_PATH = "/gateway/v1/mge/service.sbr".freeze

    def initialize(config: Sankhya::Config)
      @config = config
      @token = nil
      @token_expires_at = nil
    end

    # Executa SQL (somente leitura) e retorna Array<Hash> (coluna -> valor).
    # Levanta BurstLimitError se o resultado veio truncado (precisa paginar),
    # a menos que allow_burst: true (útil para amostragem/descoberta).
    def execute_query(sql, allow_burst: false)
      json = gateway_post(
        "DbExplorerSP.executeQuery",
        { serviceName: "DbExplorerSP.executeQuery", requestBody: { sql: sql } }
      )

      if json["status"].to_s != "1"
        raise QueryError, "Sankhya recusou a query: #{json['statusMessage'] || "status=#{json['status']}"}"
      end

      response = json.fetch("responseBody", {})
      if response["burstLimit"] && !allow_burst
        raise BurstLimitError, "Resultado truncado pelo teto de linhas do servidor — pagine a consulta (keyset por NUNOTA)."
      end

      rows_to_hashes(response)
    end

    # Token válido em cache, ou autentica sob demanda.
    def token
      return @token if @token && @token_expires_at && Time.current < @token_expires_at

      authenticate!
    end

    # Força (re)autenticação e recacheia o token.
    def authenticate!
      @config.validate!

      uri = URI.parse("#{@config.base_url}/authenticate")

      req = Net::HTTP::Post.new(uri)
      req["X-Token"] = @config.x_token
      # Credenciais vão no CORPO (form-urlencoded). O endpoint exige grant_type
      # como form parameter — na query string retorna "Missing form parameter".
      req.set_form_data(
        client_id: @config.client_id,
        client_secret: @config.client_secret,
        grant_type: "client_credentials"
      )

      res = perform(uri, req)
      unless res.is_a?(Net::HTTPSuccess)
        raise AuthError, "authenticate falhou (HTTP #{res.code}): #{truncate(res.body)}"
      end

      data = parse_json(res)
      @token = data["access_token"]
      raise AuthError, "Resposta de auth sem access_token: #{truncate(res.body)}" if @token.to_s.empty?

      ttl = Integer(data["expires_in"] || 3600) - @config.token_safety_margin
      @token_expires_at = Time.current + [ttl, 30].max
      @token
    rescue JSON::ParserError => e
      raise AuthError, "Resposta de auth não é JSON: #{e.message}"
    end

    private

    # POST autenticado no Gateway. Reautentica UMA vez em caso de 401.
    def gateway_post(service_name, body, retried: false)
      uri = URI.parse("#{@config.base_url}#{GATEWAY_PATH}")
      uri.query = URI.encode_www_form(serviceName: service_name, outputType: "json")

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)

      res = perform(uri, req)

      if res.code.to_i == 401 && !retried
        authenticate!
        return gateway_post(service_name, body, retried: true)
      end

      unless res.is_a?(Net::HTTPSuccess)
        raise RequestError, "#{service_name} falhou (HTTP #{res.code}): #{truncate(res.body)}"
      end

      parse_json(res)
    rescue JSON::ParserError => e
      raise RequestError, "Resposta do Gateway não é JSON: #{e.message}"
    end

    # Executa a requisição HTTP com TLS + timeouts.
    def perform(uri, req)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http.request(req)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise RequestError, "Timeout falando com o Sankhya: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise RequestError, "Falha de conexão com o Sankhya: #{e.message}"
    end

    # Faz o parse do JSON tratando encoding: o Gateway às vezes responde em
    # ISO-8859-1 (acentos) e quebra ao ler como UTF-8. Normaliza antes de parsear.
    def parse_json(res)
      body = res.body.to_s
      utf8 = body.dup.force_encoding("UTF-8")
      body = utf8.valid_encoding? ? utf8 : body.dup.force_encoding("ISO-8859-1").encode("UTF-8")
      JSON.parse(body)
    end

    # Zipa fieldsMetadata (ordenado por `order`) com cada linha posicional,
    # produzindo Hash coluna->valor. `rows` vêm na ordem do SELECT.
    def rows_to_hashes(response)
      names = Array(response["fieldsMetadata"])
              .sort_by { |f| f["order"].to_i }
              .map { |f| f["name"] }
      Array(response["rows"]).map { |row| names.zip(row).to_h }
    end

    def truncate(str, max = 500)
      s = str.to_s
      s.length > max ? "#{s[0, max]}…" : s
    end
  end
end
