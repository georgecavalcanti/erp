module Agent
  # Configuração do agente Claude (doc 06, "Estratégia de custos"). Segredos e
  # tetos vêm de variáveis de ambiente (Railway em produção; shell em dev).
  # A chave da Claude é SEPARADA das credenciais do Sankhya — o agente nunca
  # recebe credencial do ERP.
  #
  #   ANTHROPIC_API_KEY          # obrigatória para o agente funcionar
  #   CLAUDE_MODEL_LIGHT         # rotina (default claude-haiku-4-5)
  #   CLAUDE_MODEL_DEFAULT       # complexo (default claude-sonnet-5)
  #   AGENT_DAILY_TOKEN_BUDGET   # teto diário global de tokens (default 2M)
  module Config
    # Runtime decidido no doc 06 (19/07/2026): Haiku 4.5 para rotina, escalando
    # para Sonnet 5 nos casos complexos. Opus fica para desenvolvimento.
    DEFAULT_LIGHT_MODEL = "claude-haiku-4-5".freeze
    DEFAULT_MODEL = "claude-sonnet-5".freeze

    # Preços US$/1M tokens (platform.claude.com/docs/en/pricing, jul/2026) para o
    # cost_estimate da auditoria. Cache read ~0,1× do input.
    PRICES = {
      "claude-haiku-4-5" => { input: 1.00, output: 5.00 },
      "claude-sonnet-5"  => { input: 3.00, output: 15.00 }
    }.freeze

    def self.api_key = ENV["ANTHROPIC_API_KEY"]
    def self.light_model = ENV["CLAUDE_MODEL_LIGHT"].presence || DEFAULT_LIGHT_MODEL
    def self.default_model = ENV["CLAUDE_MODEL_DEFAULT"].presence || DEFAULT_MODEL

    # Teto diário GLOBAL de tokens (input+output). Excedido → o agente degrada
    # (última resposta válida + aviso) em vez de estourar o orçamento.
    def self.daily_token_budget = Integer(ENV.fetch("AGENT_DAILY_TOKEN_BUDGET", 2_000_000))

    # Aviso (alerta grupo IA, doc 09) ao cruzar esta fração do teto.
    def self.budget_warning_ratio = 0.8

    def self.enabled? = api_key.present?

    # US$ estimado de uma execução; modelo desconhecido → nil (não chuta preço).
    # Cache read ~0,1× do input; cache WRITE 1,25× (TTL 5min).
    def self.cost_estimate(model:, input_tokens:, output_tokens:, cache_read_tokens: 0, cache_write_tokens: 0)
      prices = PRICES[model.to_s] or return nil
      ((input_tokens * prices[:input] +
        output_tokens * prices[:output] +
        cache_read_tokens * prices[:input] * 0.1 +
        cache_write_tokens * prices[:input] * 1.25) / 1_000_000.0).round(6)
    end
  end
end
