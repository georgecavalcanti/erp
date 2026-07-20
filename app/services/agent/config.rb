module Agent
  # Configuração do agente Claude (doc 06, "Estratégia de custos"). Segredos e
  # tetos vêm de variáveis de ambiente (Railway em produção; shell em dev).
  # A chave da Claude é SEPARADA das credenciais do Sankhya — o agente nunca
  # recebe credencial do ERP.
  #
  #   ANTHROPIC_API_KEY                # obrigatória para o agente funcionar
  #   CLAUDE_MODEL_LIGHT               # rotina (default claude-haiku-4-5)
  #   CLAUDE_MODEL_DEFAULT            # complexo (default claude-sonnet-5)
  #   AGENT_MONTHLY_COST_BUDGET_USD    # teto GLOBAL de custo do MÊS (default US$ 20)
  #   AGENT_DAILY_COST_PER_SELLER_USD  # teto por vendedor/DIA (default US$ 1)
  #   AGENT_DAILY_TOKEN_BUDGET        # backstop absoluto em tokens/dia (default 2M)
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

    # Controle PRIMÁRIO de gasto: tetos de custo em US$ (o que o gestor entende).
    #   * global MENSAL: o total do MÊS "contando tudo" (copiloto + resumo +
    #     abordagens) não passa daqui — excedido, o agente degrada para TODOS até
    #     o próximo mês. É o orçamento de fato (US$ 20/mês).
    #   * por vendedor DIÁRIO: um vendedor não abusa do chat num único dia.
    # Degradação = última resposta válida + aviso (nunca estoura o orçamento).
    def self.monthly_cost_budget_usd = Float(ENV.fetch("AGENT_MONTHLY_COST_BUDGET_USD", 20.0))
    def self.daily_cost_per_seller_usd = Float(ENV.fetch("AGENT_DAILY_COST_PER_SELLER_USD", 1.0))

    # Backstop absoluto em tokens (rede de segurança se o custo estiver mal
    # estimado, ex.: modelo sem preço na tabela). Raramente é o limite ativo.
    def self.daily_token_budget = Integer(ENV.fetch("AGENT_DAILY_TOKEN_BUDGET", 2_000_000))

    # Aviso (alerta grupo IA, doc 09) ao cruzar esta fração de um teto.
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
