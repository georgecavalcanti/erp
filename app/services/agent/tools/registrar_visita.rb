module Agent
  module Tools
    # Registra uma VISITA ao cliente (activity kind=visit) — base local, doc 06.
    class RegistrarVisita < RegistrarAtividadeBase
      tool_name "registrar_visita"
      description "Registra uma visita presencial feita a um cliente da carteira. " \
                  "Escreve apenas na base local — nada vai ao ERP."
      input_schema base_schema
      activity_kind :visit
    end
  end
end
