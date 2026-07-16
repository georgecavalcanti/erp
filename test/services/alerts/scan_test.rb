require "test_helper"

module Alerts
  # Varredura de alertas operacionais (doc 09.14.2).
  class ScanTest < ActiveSupport::TestCase
    # Quinta-feira, 14h em São Paulo (dentro do horário comercial).
    BIZ = Time.new(2026, 7, 16, 14, 0, 0, "-03:00")
    NIGHT = Time.new(2026, 7, 16, 2, 0, 0, "-03:00")
    HOUR_19 = Time.new(2026, 7, 16, 19, 20, 0, "-03:00") # última varredura do cron (20 8-19)

    def keys(as_of = BIZ)
      Alerts::Scan.call(as_of: as_of)
      Alert.open.pluck(:key)
    end

    # --- Integração ----------------------------------------------------------

    test "sync atrasado dispara em horário comercial" do
      SyncRun.create!(finished_at: BIZ - 3.hours, status: "ok")
      assert_includes keys, "sync_late"
    end

    test "sync recente não dispara atraso" do
      SyncRun.create!(finished_at: BIZ - 10.minutes, status: "ok")
      assert_not_includes keys, "sync_late"
    end

    test "sync atrasado NÃO dispara de madrugada (sem sync agendado)" do
      SyncRun.create!(finished_at: NIGHT - 5.hours, status: "ok")
      assert_not_includes keys(NIGHT), "sync_late"
    end

    test "às 19:20 (última varredura) o atraso AINDA é avaliado (hora 19 é comercial)" do
      SyncRun.create!(finished_at: HOUR_19 - 3.hours, status: "ok")
      assert_includes keys(HOUR_19), "sync_late"
    end

    test "varredura fora do horário NÃO resolve um sync_late já aberto (só não reavalia)" do
      SyncRun.create!(finished_at: BIZ - 3.hours, status: "ok")
      Alerts::Scan.call(as_of: BIZ)
      assert Alert.open.exists?(key: "sync_late")

      Alerts::Scan.call(as_of: NIGHT) # de madrugada não avalia o atraso
      assert Alert.open.exists?(key: "sync_late"), "não deve resolver um check que não foi reavaliado"
    end

    test "falha na última sincronização dispara" do
      SyncRun.create!(finished_at: BIZ - 10.minutes, status: "partial", error_messages: [ "Notas: timeout" ])
      k = keys
      assert_includes k, "sync_failed"
      assert_equal "Notas: timeout", Alert.find_by(key: "sync_failed").message
    end

    test "sem nenhum sync registrado dispara sync_missing" do
      assert_includes keys, "sync_missing"
    end

    # --- Dados ---------------------------------------------------------------

    test "cliente ativo com compras e sem carteira → alerta de dados" do
      p = Partner.create!(external_code: 51_001, name: "SEM DONO", active: true)
      Invoice.create!(external_uid: 51_101, negotiation_date: Date.current, total_value: 100, kind: :sale, confirmed: true, partner: p)
      assert_includes keys, "data_partners_no_seller"
    end

    test "produto sem categoria e sem custo → alertas de dados" do
      Product.create!(external_code: 51_201, description: "X", active: true, category_external_code: nil, current_cost: nil)
      k = keys
      assert_includes k, "data_products_no_category"
      assert_includes k, "data_products_no_cost"
    end

    # --- Conciliação ---------------------------------------------------------

    test "nota com total ≠ Σ itens dispara conciliação" do
      p = Partner.create!(external_code: 51_301, name: "P")
      inv = Invoice.create!(external_uid: 51_401, negotiation_date: Date.current, total_value: 1_000,
                            kind: :sale, confirmed: true, partner: p, items_synced_at: Time.current)
      InvoiceItem.create!(invoice: inv, external_sequence: 1, quantity: 1, net_value: 800, gross_value: 800) # 800 ≠ 1000
      assert_includes keys, "recon_invoice_items_mismatch"
    end

    test "nota com total = Σ itens NÃO dispara conciliação" do
      p = Partner.create!(external_code: 51_351, name: "P2")
      inv = Invoice.create!(external_uid: 51_451, negotiation_date: Date.current, total_value: 1_000,
                            kind: :sale, confirmed: true, partner: p, items_synced_at: Time.current)
      InvoiceItem.create!(invoice: inv, external_sequence: 1, quantity: 2, net_value: 1_000, gross_value: 1_000)
      assert_not_includes keys, "recon_invoice_items_mismatch"
    end

    # --- Negócio -------------------------------------------------------------

    def active_seller_with_user(code)
      sp = Salesperson.create!(external_code: code, nickname: "V#{code}", active: true)
      User.create!(email_address: "v#{code}@x.com", password: "secret123", role: :vendedor, salesperson: sp, active: true)
      sp
    end

    test "vendedor ativo sem meta no mês → alerta de negócio" do
      sp = active_seller_with_user(51_501)
      assert_includes keys, "seller_no_goal:#{sp.id}"
    end

    test "meta de margem (sem faturamento) NÃO supre o alerta de meta ausente" do
      sp = active_seller_with_user(51_551)
      Goal.create!(salesperson: sp, period: Date.current.beginning_of_month, kind: :margin, amount: 10)
      assert_includes keys, "seller_no_goal:#{sp.id}" # só revenue conta
    end

    test "projeção provável abaixo de 60% da meta → projeção crítica" do
      sp = active_seller_with_user(51_601)
      Goal.create!(salesperson: sp, period: Date.current.beginning_of_month, kind: :revenue, amount: 100_000)
      Projection.create!(salesperson: sp, reference_date: Date.current, scenario: :likely,
                         value: 40_000, target_value: 100_000, method: "t", engine_version: "t")
      k = keys
      assert_includes k, "projection_critical:#{sp.id}"
      assert_not_includes k, "seller_no_goal:#{sp.id}" # tem meta
    end

    test "projeção saudável (≥60%) não dispara crítica" do
      sp = active_seller_with_user(51_701)
      Goal.create!(salesperson: sp, period: Date.current.beginning_of_month, kind: :revenue, amount: 100_000)
      Projection.create!(salesperson: sp, reference_date: Date.current, scenario: :likely,
                         value: 80_000, target_value: 100_000, method: "t", engine_version: "t")
      assert_not_includes keys, "projection_critical:#{sp.id}"
    end

    # --- Ciclo de vida (cria / atualiza / resolve) ---------------------------

    test "resolve o alerta quando a condição deixa de ocorrer" do
      run = SyncRun.create!(finished_at: BIZ - 3.hours, status: "ok")
      Alerts::Scan.call(as_of: BIZ)
      assert Alert.open.exists?(key: "sync_late")

      run.update!(finished_at: BIZ - 5.minutes) # sync ficou fresco
      Alerts::Scan.call(as_of: BIZ)
      assert_not Alert.open.exists?(key: "sync_late")
      assert Alert.resolved.exists?(key: "sync_late")
    end

    test "não duplica: reexecução mantém o mesmo alerta aberto e atualiza detecção" do
      SyncRun.create!(finished_at: BIZ - 3.hours, status: "ok")
      Alerts::Scan.call(as_of: BIZ)
      Alerts::Scan.call(as_of: BIZ + 1.hour)
      assert_equal 1, Alert.where(key: "sync_late").count
      assert_equal (BIZ + 1.hour).to_i, Alert.find_by(key: "sync_late").last_detected_at.to_i
    end
  end
end
