require "test_helper"

module Agent
  # Grupo Ação preparada (doc 06): escreve SOMENTE na base local (activities/
  # recommendations) com autoria do usuário autenticado — nunca envia nada,
  # nunca toca o ERP, sempre no limite da carteira.
  class ActionToolsTest < ActiveSupport::TestCase
    setup do
      @sp = Salesperson.create!(external_code: 95_001, nickname: "VEND.AC")
      @user = User.create!(email_address: "ac@teste.local", password: "senha-secreta",
                           role: :vendedor, salesperson: @sp)
      @uid = 95_100

      @cliente = Partner.create!(external_code: (@uid += 1), name: "Cliente Ação")
      Wallet.create!(salesperson: @sp, partner: @cliente, starts_on: 1.year.ago)

      @alheio = Partner.create!(external_code: (@uid += 1), name: "Cliente Alheio")
      outro = Salesperson.create!(external_code: 95_002, nickname: "OUTRO")
      Wallet.create!(salesperson: outro, partner: @alheio, starts_on: 1.year.ago)
    end

    def registry
      ToolRegistry.new(user: @user, salesperson: @sp)
    end

    test "registrar_contato cria activity com autoria e canal" do
      result = registry.call("registrar_contato",
                             { "partner_id" => @cliente.id, "notas" => "Falamos sobre o pedido de julho",
                               "canal" => "ligacao" })
      assert result[:ok], result[:error]

      activity = Activity.find(result[:data][:atividade_id])
      assert activity.kind_contact?
      assert_equal @user, activity.user
      assert_equal @sp, activity.salesperson
      assert_equal "ligacao", activity.channel
    end

    test "registrar_visita e registrar_observacao gravam os kinds corretos" do
      v = registry.call("registrar_visita", { "partner_id" => @cliente.id, "notas" => "Visita ao depósito" })
      o = registry.call("registrar_observacao", { "partner_id" => @cliente.id, "notas" => "Prefere entrega às sextas" })
      assert Activity.find(v[:data][:atividade_id]).kind_visit?
      assert Activity.find(o[:data][:atividade_id]).kind_note?
    end

    test "ações negam cliente de outra carteira" do
      %w[registrar_contato registrar_visita registrar_observacao].each do |tool|
        result = registry.call(tool, { "partner_id" => @alheio.id, "notas" => "tentativa" })
        assert_not result[:ok], "#{tool} deveria negar cliente alheio"
      end
      assert_equal 0, Activity.where(partner: @alheio).count, "nenhuma escrita fora da carteira"
    end

    test "criar_tarefa exige prazo futuro e grava em outcome" do
      passado = registry.call("criar_tarefa", { "partner_id" => @cliente.id, "notas" => "Ligar",
                                                "prazo" => (Date.current - 1).iso8601 })
      assert_not passado[:ok]
      assert_match(/passado/, passado[:error])

      futuro = registry.call("criar_tarefa", { "partner_id" => @cliente.id, "notas" => "Ligar para fechar",
                                               "prazo" => (Date.current + 2).iso8601 })
      assert futuro[:ok], futuro[:error]
      activity = Activity.find(futuro[:data][:atividade_id])
      assert activity.kind_task?
      assert_equal (Date.current + 2).iso8601, activity.outcome["prazo"]
    end

    test "registrar_resultado conclui a recomendação e cria receita influenciada" do
      rec = Recommendation.create!(salesperson: @sp, partner: @cliente, reference_date: Date.current,
                                   status: :accepted)
      nota = Invoice.create!(external_uid: (@uid += 1), negotiation_date: Date.current,
                             total_value: 2_000, kind: :sale, confirmed: true,
                             partner: @cliente, salesperson: @sp)

      result = registry.call("registrar_resultado",
                             { "recommendation_id" => rec.id, "valor" => 2_000,
                               "nota_uid" => nota.external_uid, "notas" => "Fechou o pedido" })
      assert result[:ok], result[:error]

      rec.reload
      assert rec.status_done?
      assert_equal 1, rec.influenced_revenues.count
      assert_equal nota.id, rec.influenced_revenues.first.invoice_id
      assert Activity.where(recommendation: rec).exists?
    end

    test "registrar_resultado rejeita nota de outro cliente" do
      rec = Recommendation.create!(salesperson: @sp, partner: @cliente, reference_date: Date.current)
      nota_alheia = Invoice.create!(external_uid: (@uid += 1), negotiation_date: Date.current,
                                    total_value: 500, kind: :sale, confirmed: true,
                                    partner: @alheio, salesperson: @sp)

      result = registry.call("registrar_resultado",
                             { "recommendation_id" => rec.id, "valor" => 500, "nota_uid" => nota_alheia.external_uid })
      assert_not result[:ok]
      assert_match(/não encontrada para este cliente/, result[:error])
    end

    test "registrar_resultado nega recomendação de vendedor fora do escopo" do
      outro_sp = Salesperson.find_by(external_code: 95_002)
      rec = Recommendation.create!(salesperson: outro_sp, partner: @alheio, reference_date: Date.current)

      result = registry.call("registrar_resultado", { "recommendation_id" => rec.id, "valor" => 100 })
      assert_not result[:ok]
      assert_match(/fora do seu escopo/, result[:error])
    end

    test "preparar_mensagem salva rascunho e deixa claro que nada foi enviado" do
      result = registry.call("preparar_mensagem",
                             { "partner_id" => @cliente.id, "canal" => "whatsapp",
                               "texto" => "Olá! Vi que sua última compra de sulfite foi há 40 dias..." })
      assert result[:ok], result[:error]
      assert_match(/nada foi enviado/i, result[:data][:aviso])

      activity = Activity.find(result[:data][:atividade_id])
      assert_equal "rascunho_mensagem", activity.outcome["tipo"]
      assert_match(/NÃO enviado/, activity.notes)
    end

    test "preparar_cotacao valida itens no catálogo e não inclui preços" do
      produto = Product.create!(external_code: (@uid += 1), description: "Papel Toalha", active: true)

      invalido = registry.call("preparar_cotacao",
                               { "partner_id" => @cliente.id,
                                 "itens" => [ { "codigo" => 999_999_999, "quantidade" => 5 } ] })
      assert_not invalido[:ok]
      assert_match(/não encontrado no catálogo/, invalido[:error])

      result = registry.call("preparar_cotacao",
                             { "partner_id" => @cliente.id,
                               "itens" => [ { "codigo" => produto.external_code, "quantidade" => 5 } ] })
      assert result[:ok], result[:error]
      activity = Activity.find(result[:data][:atividade_id])
      assert_equal "rascunho_cotacao", activity.outcome["tipo"]
      item = result[:data][:itens].first
      assert_nil item[:preco], "cotação nunca carrega preço (fonte não integrada)"
      assert_match(/sem preços/, result[:data][:aviso])
    end
  end
end
