module Agent
  module Tools
    # Preço vigente (doc 06). A tabela de preços do Sankhya (TGFTAB/TGFEXC) ainda
    # NÃO está integrada ao espelho — regra do doc 06: nunca informar preço sem
    # consulta válida. A ferramenta existe no registry para o agente responder a
    # ausência com honestidade (e orientar o vendedor), em vez de alucinar valor.
    # Quando o sync de preços existir, este execute passa a consultá-lo.
    class ConsultarPrecos < BaseTool
      tool_name "consultar_precos"
      description "Preço vigente e tabela aplicável de um produto. ATENÇÃO: se a fonte estiver " \
                  "indisponível, informe a indisponibilidade ao vendedor — nunca estime preço."
      input_schema({
        type: "object",
        properties: {
          produto: { type: "string", minLength: 2,
                     description: "Código do produto (CODPROD) ou termo da descrição" }
        },
        required: [ "produto" ],
        additionalProperties: false
      })

      def execute(_params)
        {
          disponivel: false,
          aviso: "A tabela de preços ainda não está integrada à base local. " \
                 "Oriente o vendedor a consultar o preço vigente diretamente no Sankhya antes de propor valores. " \
                 "NÃO estime nem sugira preços."
        }
      end
    end
  end
end
