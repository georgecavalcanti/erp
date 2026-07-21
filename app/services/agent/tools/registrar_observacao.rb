module Agent
  module Tools
    # Registra uma OBSERVAÇÃO sobre o cliente (activity kind=note) — base local, doc 06.
    class RegistrarObservacao < RegistrarAtividadeBase
      tool_name "registrar_observacao"
      description "Registra uma observação sobre um cliente da carteira (contexto, preferência, " \
                  "restrição comercial informada pelo vendedor). Base local apenas."
      input_schema base_schema
      activity_kind :note
    end
  end
end
