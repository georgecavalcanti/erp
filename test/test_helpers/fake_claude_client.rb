# Cliente falso da Claude API para os testes do agente (mesmo padrão do
# FakeSankhyaClient): NUNCA bate na rede. Recebe um ROTEIRO de respostas —
# cada `messages.create` consome a próxima — e grava os parâmetros de cada
# request para inspeção (system_, tools, messages, output_config).
class FakeClaudeClient
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens)
  TextBlock = Struct.new(:type, :text)
  ToolUseBlock = Struct.new(:type, :id, :name, :input)
  ThinkingBlock = Struct.new(:type, :thinking, :signature)
  Response = Struct.new(:stop_reason, :content, :usage)

  attr_reader :requests

  def initialize(script)
    @script = script.dup
    @requests = []
  end

  # O orquestrador chama client.messages.create(...) — self responde pelos dois.
  def messages = self

  def create(**params)
    # Congela o retrato do request: o orquestrador segue mutando o array
    # `messages` depois da chamada — sem o dup, toda inspeção veria o estado final.
    @requests << params.merge(messages: params[:messages].dup)
    step = @script.shift or raise "FakeClaudeClient: roteiro esgotado (request inesperado)"
    step.respond_to?(:call) ? step.call(params) : step
  end

  DEFAULT_USAGE = [ 1_000, 200, 0, 0 ].freeze

  # Resposta final de texto (o JSON do structured output vem como string).
  def self.final(payload, usage: DEFAULT_USAGE, stop_reason: :end_turn)
    text = payload.is_a?(String) ? payload : JSON.generate(payload)
    Response.new(stop_reason, [ TextBlock.new(:text, text) ], Usage.new(*usage))
  end

  # Resposta pedindo ferramenta(s): [[nome, input], ...]. thinking: simula o
  # adaptive thinking do Sonnet 5 (bloco que DEVE voltar intacto no reenvio).
  def self.tool_use(*calls, usage: DEFAULT_USAGE, thinking: nil)
    blocks = calls.each_with_index.map do |(name, input), i|
      ToolUseBlock.new(:tool_use, "toolu_#{i + 1}", name, input || {})
    end
    blocks.unshift(ThinkingBlock.new(:thinking, thinking, "sig_teste")) if thinking
    Response.new(:tool_use, blocks, Usage.new(*usage))
  end

  def self.refusal(usage: DEFAULT_USAGE)
    Response.new(:refusal, [], Usage.new(*usage))
  end
end
