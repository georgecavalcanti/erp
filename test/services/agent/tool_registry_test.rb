require "test_helper"

module Agent
  # Segurança das ferramentas do agente (doc 06/07/09): allowlist fail-closed,
  # escopo por carteira injetado pela aplicação e ausência de dado explícita.
  class ToolRegistryTest < ActiveSupport::TestCase
    setup do
      @sp_a = Salesperson.create!(external_code: 91_001, nickname: "VEND.A")
      @sp_b = Salesperson.create!(external_code: 91_002, nickname: "VEND.B")
      @user_a = User.create!(email_address: "va@teste.local", password: "senha-secreta",
                             role: :vendedor, salesperson: @sp_a)
      @admin = users(:one)

      @cliente_a = Partner.create!(external_code: 92_001, name: "Cliente da Carteira A")
      @cliente_b = Partner.create!(external_code: 92_002, name: "Cliente da Carteira B")
      Wallet.create!(salesperson: @sp_a, partner: @cliente_a, starts_on: 1.year.ago)
      Wallet.create!(salesperson: @sp_b, partner: @cliente_b, starts_on: 1.year.ago)
    end

    def registry(user: @user_a, salesperson: user.salesperson)
      ToolRegistry.new(user: user, salesperson: salesperson)
    end

    # --- Allowlist (doc 09: capacidade inexistente = capacidade negada) ---

    test "ferramenta fora do registry é negada, nunca executada" do
      result = registry.call("alterar_preco", { "produto" => 1, "novo_preco" => 10 })
      assert_not result[:ok]
      assert_match(/não existe/, result[:error])
    end

    test "definitions expõe as 9 ferramentas de consulta em ordem determinística" do
      defs = registry.definitions
      assert_equal defs.map { |d| d[:name] }, registry.definitions.map { |d| d[:name] }
      assert_includes defs.map { |d| d[:name] }, "consultar_cliente_360"
      assert_equal 9, defs.size
      # Nenhum schema expõe parâmetro de escopo — o modelo não escolhe vendedor.
      defs.each do |d|
        assert_not_includes d[:input_schema][:properties].keys.map(&:to_s), "salesperson_id",
                            "#{d[:name]} não pode expor escopo de vendedor"
      end
    end

    # --- Isolamento por carteira (regra de ouro, doc 07) ---

    test "vendedor A não consulta cliente 360 da carteira de B" do
      result = registry.call("consultar_cliente_360", { "partner_id" => @cliente_b.id })
      assert_not result[:ok]
      assert_match(/fora da sua carteira/, result[:error])
    end

    test "vendedor A consulta cliente da própria carteira" do
      result = registry.call("consultar_cliente_360", { "partner_id" => @cliente_a.id })
      assert result[:ok], result[:error]
      assert_equal "Cliente da Carteira A", result[:data][:cadastro][:name]
    end

    test "isolamento vale para vendas, crédito e interações" do
      %w[consultar_vendas_cliente consultar_credito consultar_interacoes].each do |tool|
        result = registry.call(tool, { "partner_id" => @cliente_b.id })
        assert_not result[:ok], "#{tool} deveria negar cliente de outra carteira"
      end
    end

    test "admin (irrestrito) consulta qualquer cliente" do
      result = registry(user: @admin, salesperson: @sp_b).call(
        "consultar_credito", { "partner_id" => @cliente_b.id }
      )
      assert result[:ok], result[:error]
      assert_equal "Cliente da Carteira B", result[:data][:cliente]
    end

    test "cliente inexistente é erro de parâmetro, não vazamento" do
      result = registry.call("consultar_cliente_360", { "partner_id" => 999_999 })
      assert_not result[:ok]
      assert_match(/não encontrado/, result[:error])
    end

    # --- Ausência de dado explícita (doc 06: não inventar) ---

    test "consultar_meta sem meta cadastrada devolve ausência, não valor" do
      result = registry.call("consultar_meta", {})
      assert result[:ok]
      assert_empty result[:data][:metas]
      assert_match(/Nenhuma meta cadastrada/, result[:data][:aviso])
    end

    test "consultar_meta com meta devolve os valores do período" do
      Goal.create!(salesperson: @sp_a, period: Date.current, kind: :revenue, amount: 150_000)
      result = registry.call("consultar_meta", { "mes" => Date.current.strftime("%Y-%m") })
      assert result[:ok]
      assert_equal 150_000.0, result[:data][:metas].first[:valor]
    end

    test "consultar_precos declara fonte indisponível e proíbe estimativa" do
      result = registry.call("consultar_precos", { "produto" => "papel" })
      assert result[:ok]
      assert_equal false, result[:data][:disponivel]
      assert_match(/NÃO estime/, result[:data][:aviso])
    end

    test "consultar_estoque sem correspondência responde ausência" do
      result = registry.call("consultar_estoque", { "produto" => "produto-que-nao-existe-xyz" })
      assert result[:ok]
      assert_empty result[:data][:produtos]
      assert_match(/Nenhum produto/, result[:data][:aviso])
    end

    test "consultar_estoque com vários candidatos usa snapshot e avisa" do
      2.times do |i|
        p = Product.create!(external_code: 93_000 + i, description: "Papel Sulfite A#{i}", active: true)
        StockLevel.create!(product: p, on_hand: 10 + i, reserved: 0, synced_at: Time.current)
      end
      result = registry.call("consultar_estoque", { "produto" => "Papel Sulfite" })
      assert result[:ok]
      assert_equal 2, result[:data][:produtos].size
      assert(result[:data][:produtos].all? { |p| p[:origem] == "snapshot" })
    end

    # --- Contexto de vendedor obrigatório ---

    test "ferramenta de vendedor sem contexto de vendedor falha com orientação" do
      result = ToolRegistry.new(user: @admin, salesperson: nil).call("consultar_meta", {})
      assert_not result[:ok]
      assert_match(/exige um vendedor/, result[:error])
    end

    # --- Robustez: falha interna não derruba o loop ---

    test "erro interno vira tool_result de indisponibilidade" do
      Customer360Report.define_singleton_method(:new) { |*| raise "boom" }
      result = registry.call("consultar_cliente_360", { "partner_id" => @cliente_a.id })
      assert_not result[:ok]
      assert_match(/indisponível/, result[:error])
    ensure
      Customer360Report.singleton_class.remove_method(:new)
    end
  end
end
