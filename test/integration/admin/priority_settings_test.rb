require "test_helper"

module Admin
  # Config de priorização: só gestão edita; alterar a capacidade afeta o plano.
  class PrioritySettingsTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "adm@x.com", password: "secret123", role: :administrador)
      sp = Salesperson.create!(external_code: 11_001, nickname: "V")
      @vendedor = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: sp)
    end

    test "gestão abre a configuração" do
      sign_in_as(@admin)
      get admin_priorizacao_path
      assert_inertia_component "admin/PrioritySettings"
      assert_equal 12, inertia.props[:setting][:daily_capacity] # default do doc
    end

    test "salvar altera os pesos e a capacidade" do
      sign_in_as(@admin)
      patch admin_priorizacao_path, params: { daily_capacity: 5, weight_margin: 30 }
      assert_equal 5, PrioritySetting.current.daily_capacity
      assert_equal 30, PrioritySetting.current.weight_margin
    end

    test "vendedor NÃO acessa a configuração" do
      sign_in_as(@vendedor)
      get admin_priorizacao_path
      assert_redirected_to root_path
      assert_match(/restrito/i, flash[:alert])
    end
  end
end
