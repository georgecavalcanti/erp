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

      # Cliente autorizado ou Denied. É o MESMO limite das telas (AccessPolicy).
      def authorized_partner!(partner_id)
        raise Invalid, "Informe partner_id." if partner_id.blank?

        partner = Partner.find_by(id: partner_id)
        raise Invalid, "Cliente #{partner_id} não encontrado." unless partner
        unless access.can_view_partner?(partner.id)
          raise Denied, "Cliente fora da sua carteira — acesso negado."
        end

        partner
      end

      # BigDecimal não serializa bem para o modelo — sempre Float com 2 casas.
      def money(value)
        value.nil? ? nil : value.to_f.round(2)
      end
    end
  end
end
