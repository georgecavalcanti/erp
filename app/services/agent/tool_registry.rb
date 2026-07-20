module Agent
  # Registro das ferramentas autorizadas do agente (doc 06/09). É a ALLOWLIST:
  # capacidade que não está aqui NÃO EXISTE — pedido de ferramenta desconhecida
  # vira erro (nunca execução). O registry injeta o usuário autenticado e o
  # vendedor de contexto em toda ferramenta; o modelo nunca escolhe escopo.
  #
  #   registry = Agent::ToolRegistry.new(user: Current.user, salesperson: sp)
  #   registry.definitions        # schemas p/ a Claude API (ordem determinística → cache)
  #   registry.call(name, params) # => { ok: true, data: } | { ok: false, error: }
  class ToolRegistry
    # Grupos do doc 06. A ordem é ESTÁVEL (e as listas congeladas) de propósito:
    # tools renderizam antes do system no prompt — ordem determinística preserva
    # o prompt cache entre chamadas.
    CONSULTA = [
      Tools::ConsultarMeta, Tools::ConsultarResultadoVendedor, Tools::ConsultarCliente360,
      Tools::ConsultarVendasCliente, Tools::ConsultarPedidosAbertos, Tools::ConsultarEstoque,
      Tools::ConsultarPrecos, Tools::ConsultarCredito, Tools::ConsultarInteracoes
    ].freeze
    ANALISE = [
      Tools::CalcularProjecao, Tools::PreverRecompra, Tools::DetectarClientesEmRisco,
      Tools::DetectarQuedaDeConsumo, Tools::IdentificarCrossSell, Tools::CalcularPotencialCliente,
      Tools::PriorizarCarteira, Tools::SimularPlanoParaMeta
    ].freeze
    ACAO = [
      Tools::RegistrarContato, Tools::RegistrarVisita, Tools::RegistrarObservacao,
      Tools::CriarTarefa, Tools::RegistrarResultado, Tools::PrepararMensagem, Tools::PrepararCotacao
    ].freeze
    TOOL_CLASSES = (CONSULTA + ANALISE + ACAO).freeze

    def initialize(user:, salesperson: nil)
      @user = user
      @salesperson = salesperson
    end

    # Schemas no formato da Claude API. Ordem fixa de TOOL_CLASSES (determinística).
    def definitions
      TOOL_CLASSES.map(&:definition)
    end

    def known?(name)
      index.key?(name.to_s)
    end

    # Executa uma ferramenta pelo nome vindo do modelo. NUNCA levanta exceção —
    # devolve { ok:, ... } para o orquestrador transformar em tool_result
    # (is_error quando ok: false), mantendo o loop vivo e auditável.
    def call(name, params)
      klass = index[name.to_s]
      # Allowlist (doc 09): ferramenta desconhecida = capacidade negada.
      return { ok: false, error: "Ferramenta '#{name}' não existe. Use apenas as ferramentas disponíveis." } unless klass

      # deep_stringify: o input do SDK vem com chaves Symbol também nos hashes
      # ANINHADOS (ex.: itens de preparar_cotacao) — stringify raso quebraria.
      data = klass.new(user: @user, salesperson: @salesperson).execute(params.to_h.deep_stringify_keys)
      { ok: true, data: data }
    rescue Tools::BaseTool::Denied => e
      { ok: false, error: e.message }
    rescue Tools::BaseTool::Invalid => e
      { ok: false, error: e.message }
    rescue StandardError => e
      # Falha interna não derruba a conversa; o agente reporta indisponibilidade.
      Rails.logger.error("[Agent::ToolRegistry] #{name}: #{e.class} #{e.message}")
      { ok: false, error: "Ferramenta '#{name}' indisponível no momento." }
    end

    private

    def index
      @index ||= TOOL_CLASSES.index_by(&:tool_name)
    end
  end
end
