require "test_helper"

module Agent
  # Grupo Análise (doc 06): as ferramentas devolvem o resultado dos MOTORES
  # (persistido quando existe, ao vivo como fallback), sempre no escopo da
  # carteira injetada.
  class AnalysisToolsTest < ActiveSupport::TestCase
    AS_OF = Date.current

    setup do
      @sp = Salesperson.create!(external_code: 94_001, nickname: "VEND.AN")
      @user = User.create!(email_address: "an@teste.local", password: "senha-secreta",
                           role: :vendedor, salesperson: @sp)
      @outro_sp = Salesperson.create!(external_code: 94_002, nickname: "VEND.OUTRO")
      @uid = 94_100

      @cliente = partner_in_wallet
      @alheio = Partner.create!(external_code: (@uid += 1), name: "Cliente Alheio")
      Wallet.create!(salesperson: @outro_sp, partner: @alheio, starts_on: 1.year.ago)
    end

    def partner_in_wallet(**attrs)
      p = Partner.create!({ external_code: (@uid += 1), name: "Cliente #{@uid}", active: true }.merge(attrs))
      Wallet.create!(salesperson: @sp, partner: p, starts_on: 1.year.ago)
      p
    end

    def sale(partner, value, date: AS_OF - 20)
      Invoice.create!(external_uid: (@uid += 1), negotiation_date: date, total_value: value,
                      kind: :sale, confirmed: true, partner: partner, salesperson: @sp,
                      margin_value: value * 0.3)
    end

    def registry(salesperson: @sp)
      ToolRegistry.new(user: @user, salesperson: salesperson)
    end

    # --- Persistido vem antes do recálculo (regra do grupo, doc 06) ---

    test "calcular_projecao devolve a leva persistida quando existe" do
      %i[conservative likely potential].each do |scenario|
        Projection.create!(salesperson: @sp, reference_date: AS_OF, scenario: scenario,
                           value: 1000, confidence: 80, method: "t", engine_version: "vteste",
                           components: { "parcels" => [ { "key" => "realizado", "value" => 1000 } ] })
      end

      result = registry.call("calcular_projecao", {})
      assert result[:ok], result[:error]
      assert_match(/persistida/, result[:data][:origem])
      assert_match(/vteste/, result[:data][:origem])
      assert_equal 3, result[:data][:cenarios].size
      assert result[:data][:cenarios].first[:parcelas].present?, "parcelas rastreáveis (explicabilidade)"
    end

    test "calcular_projecao sem leva persistida calcula ao vivo e declara a origem" do
      result = registry.call("calcular_projecao", {})
      assert result[:ok]
      assert_match(/calculada agora/, result[:data][:origem])
    end

    test "prever_recompra devolve previsões persistidas abertas com atraso calculado" do
      RepurchasePrediction.create!(partner: @cliente, level: :customer, target_key: "customer",
                                   status: :open, last_purchase_on: AS_OF - 40, expected_date: AS_OF - 5,
                                   expected_value: 800, interval_days: 30, confidence: 70,
                                   method: "t", engine_version: "t")

      result = registry.call("prever_recompra", { "partner_id" => @cliente.id })
      assert result[:ok], result[:error]
      pred = result[:data][:previsoes].first
      assert_equal 5, pred[:atrasada_dias]
      assert_equal 800.0, pred[:valor_esperado]
    end

    test "prever_recompra sem histórico declara insuficiência — não inventa" do
      result = registry.call("prever_recompra", { "partner_id" => @cliente.id })
      assert result[:ok]
      assert_empty result[:data][:previsoes]
      assert_match(/insuficiente/, result[:data][:aviso])
    end

    test "priorizar_carteira usa o plano persistido do dia quando existe" do
      Priority.create!(salesperson: @sp, partner: @cliente, reference_date: AS_OF, score: 87.5,
                       position: 1, potential_value: 1200, urgency: 90,
                       reasons: [ { "key" => "recompra_atrasada", "label" => "Recompra atrasada" } ],
                       restrictions: [], suggested_action: "Ligar hoje")

      result = registry.call("priorizar_carteira", {})
      assert result[:ok], result[:error]
      assert_match(/persistido/, result[:data][:origem])
      top = result[:data][:prioridades].first
      assert_equal @cliente.name, top[:cliente]
      assert_includes top[:motivos], "Recompra atrasada"
    end

    # --- Escopo: análise por cliente respeita a carteira ---

    test "análises por cliente negam cliente de outra carteira" do
      %w[prever_recompra identificar_cross_sell calcular_potencial_cliente].each do |tool|
        result = registry.call(tool, { "partner_id" => @alheio.id })
        assert_not result[:ok], "#{tool} deveria negar cliente alheio"
        assert_match(/fora da sua carteira/, result[:error])
      end
    end

    test "detectar_clientes_em_risco só varre a carteira do vendedor" do
      # Cliente próprio inadimplente (em risco) e alheio idem — só o próprio aparece.
      # Histórico antigo o bastante para não cair em "novo em ativação" (que tem
      # precedência sobre risco na classificação).
      sale(@cliente, 1_000, date: AS_OF - 200)
      sale(@cliente, 1_000, date: AS_OF - 120)
      sale(@cliente, 1_000, date: AS_OF - 30)
      OverdueTitle.create!(partner_id: @cliente.id, amount: 500, category: :open,
                           salesperson_label: "X", days_overdue: 30)
      OverdueTitle.create!(partner_id: @alheio.id, amount: 900, category: :open,
                           salesperson_label: "X", days_overdue: 30)

      result = registry.call("detectar_clientes_em_risco", {})
      assert result[:ok], result[:error]
      ids = result[:data][:clientes].map { |c| c[:partner_id] }
      assert_includes ids, @cliente.id
      assert_not_includes ids, @alheio.id
    end

    test "calcular_potencial_cliente decompõe recompra + cross-sell + queda" do
      RepurchasePrediction.create!(partner: @cliente, level: :customer, target_key: "customer",
                                   status: :open, expected_date: AS_OF + 5, expected_value: 700,
                                   interval_days: 30, confidence: 60, method: "t", engine_version: "t")

      result = registry.call("calcular_potencial_cliente", { "partner_id" => @cliente.id })
      assert result[:ok], result[:error]
      assert_equal 700.0, result[:data][:decomposicao][:recompras_abertas]
      assert result[:data][:potencial_total] >= 700.0
    end

    test "simular_plano_para_meta sem meta declara ausência do gap" do
      result = registry.call("simular_plano_para_meta", {})
      assert result[:ok], result[:error]
      assert_nil result[:data][:gap]
      assert_match(/Sem meta cadastrada/, result[:data][:aviso])
    end
  end
end
