module Agent
  module Tools
    # Registra um CONTATO com o cliente (activity kind=contact) — base local, doc 06.
    class RegistrarContato < RegistrarAtividadeBase
      tool_name "registrar_contato"
      description "Registra um contato realizado com um cliente da carteira (ligação, WhatsApp, e-mail). " \
                  "Escreve apenas na base local — nada é enviado ao cliente nem ao ERP."
      input_schema base_schema
      activity_kind :contact
    end
  end
end
