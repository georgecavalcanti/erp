module Agent
  module Tools
    # Contrato base de toda ferramenta do agente (doc 06). Três regras de ouro:
    #
    # 1. O ESCOPO é injetado pela aplicação (user + salesperson resolvidos e
    #    validados pelo controller via AccessPolicy) — o modelo NUNCA escolhe
    #    escopo. Os schemas expostos ao Claude não têm parâmetro de vendedor.
    # 2. Toda referência a cliente passa por `authorized_partner!` — vendedor A
    #    jamais lê dado da carteira de B (fail-closed).
    # 3. Ferramenta devolve DADO ou AUSÊNCIA explícita — nunca inventa. Falta de
    #    fonte vira aviso honesto no payload.
    #
    # Subclasses declaram `tool_name`, `description` e `input_schema` (JSON
    # Schema com additionalProperties: false) e implementam `execute(params)`
    # devolvendo um Hash serializável.
    class BaseTool
      # Escopo negado (cliente fora da carteira) — vira tool_result de erro.
      class Denied < StandardError; end
      # Parâmetro inválido/faltando — o modelo pode corrigir e tentar de novo.
      class Invalid < StandardError; end

      class << self
        def tool_name(value = nil)
          @tool_name = value if value
          @tool_name or raise NotImplementedError, "#{name} sem tool_name"
        end

        def description(value = nil)
          @description = value if value
          @description or raise NotImplementedError, "#{name} sem description"
        end

        def input_schema(value = nil)
          @input_schema = value if value
          @input_schema || { type: "object", properties: {}, additionalProperties: false }
        end

        # Definição no formato da Claude API (tools: [...]).
        def definition
          { name: tool_name, description: description, input_schema: input_schema }
        end
      end

      def initialize(user:, salesperson: nil)
        @user = user
        @salesperson = salesperson
        @access = AccessPolicy.new(user)
      end

      def execute(params)
        raise NotImplementedError
      end

      protected

      attr_reader :user, :access

      # Vendedor do contexto (resolvido pelo controller, nunca pelo modelo).
      # Ferramentas de meta/resultado/carteira não funcionam sem ele.
      def salesperson!
        @salesperson or raise Invalid, "Nenhum vendedor no contexto — esta consulta exige um vendedor."
      end

      # Cliente autorizado ou Denied. DOIS limites, ambos obrigatórios:
      #   1. o do USUÁRIO (AccessPolicy — mesmo limite das telas);
      #   2. o da CONVERSA: com vendedor de contexto, só a carteira DELE — um
      #      gestor no copiloto do vendedor A não conversa sobre cliente de B
      #      (revisão cruzada Sprint 8: sem isso, o card persistido vazaria
      #      dado de carteira alheia para o plano do vendedor A).
      def authorized_partner!(partner_id)
        raise Invalid, "Informe partner_id." if partner_id.blank?

        partner = Partner.find_by(id: partner_id)
        raise Invalid, "Cliente #{partner_id} não encontrado." unless partner
        unless access.can_view_partner?(partner.id)
          raise Denied, "Cliente fora da sua carteira — acesso negado."
        end
        if @salesperson && !context_wallet_ids.include?(partner.id)
          raise Denied, "Cliente fora da carteira do vendedor em contexto — acesso negado."
        end

        partner
      end

      # Carteira vigente do vendedor de contexto (memoizada por execução).
      def context_wallet_ids
        @context_wallet_ids ||= Wallet.active.where(salesperson_id: @salesperson.id).distinct.pluck(:partner_id)
      end

      # Coerção de parâmetro numérico opcional: o modelo às vezes manda string
      # ("6") — erro claro e corrigível em vez de NoMethodError genérico.
      def int_param(value, default:, range:)
        return default if value.blank?

        Integer(value).clamp(range.min, range.max)
      rescue ArgumentError, TypeError
        raise Invalid, "Parâmetro numérico inválido: #{value.inspect}."
      end

      # BigDecimal não serializa bem para o modelo — sempre Float com 2 casas.
      def money(value)
        value.nil? ? nil : value.to_f.round(2)
      end
    end
  end
end
