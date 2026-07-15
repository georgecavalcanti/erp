require "test_helper"

module Admin
  # Elevação de privilégio na administração: quem pode abrir e agir em cada tela.
  # Matriz do doc 07: usuários = só admin; carteiras/metas = gestor + admin.
  class AccessControlTest < ActionDispatch::IntegrationTest
    setup do
      @sp = Salesperson.create!(external_code: 5001, nickname: "S")
      @vend = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
      @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
      @admin = User.create!(email_address: "a@x.com", password: "secret123", role: :administrador)
    end

    test "vendedor não acessa nenhuma tela de administração" do
      sign_in_as(@vend)

      get admin_usuarios_path
      assert_redirected_to root_path
      get admin_carteiras_path
      assert_redirected_to root_path
      get admin_metas_path
      assert_redirected_to root_path
    end

    test "gestor acessa carteiras e metas, mas não usuários" do
      sign_in_as(@gestor)

      get admin_carteiras_path
      assert_response :success
      get admin_metas_path
      assert_response :success
      get admin_usuarios_path
      assert_redirected_to root_path
    end

    test "admin acessa todas as telas de administração" do
      sign_in_as(@admin)

      get admin_usuarios_path
      assert_response :success
      get admin_carteiras_path
      assert_response :success
      get admin_metas_path
      assert_response :success
    end

    test "admin cria vendedor vinculado (sem auto-registro)" do
      sign_in_as(@admin)
      sp2 = Salesperson.create!(external_code: 5002, nickname: "S2")

      assert_difference -> { User.count }, 1 do
        post admin_usuarios_path, params: {
          email_address: "novo@x.com", password: "secret123", role: "vendedor", salesperson_id: sp2.id
        }
      end
      novo = User.find_by(email_address: "novo@x.com")
      assert novo.role_vendedor?
      assert_equal sp2.id, novo.salesperson_id
      assert_redirected_to admin_usuarios_path
    end

    test "vendedor bloqueado não cria meta" do
      sign_in_as(@vend)

      assert_no_difference -> { Goal.count } do
        post admin_metas_path, params: { salesperson_id: @sp.id, period: "2026-07", kind: "revenue", amount: 5000 }
      end
    end

    test "meta criada fica vinculada ao vendedor e ao período corretos (MVP 4)" do
      sign_in_as(@admin)

      assert_difference -> { Goal.count }, 1 do
        post admin_metas_path, params: { salesperson_id: @sp.id, period: "2026-07", kind: "revenue", amount: 5000 }
      end
      goal = Goal.last
      assert_equal @sp.id, goal.salesperson_id
      assert_equal Date.new(2026, 7, 1), goal.period
      assert goal.kind_revenue?
      assert_equal @admin.id, goal.created_by_id
    end

    test "admin não pode se auto-rebaixar (self-lockout)" do
      sign_in_as(@admin)

      patch admin_usuario_path(@admin), params: { role: "gestor_comercial" }

      assert_redirected_to edit_admin_usuario_path(@admin)
      assert @admin.reload.role_administrador? # inalterado
    end

    test "admin não pode se auto-desativar" do
      sign_in_as(@admin)

      patch admin_usuario_path(@admin), params: { active: "false" }

      assert_redirected_to edit_admin_usuario_path(@admin)
      assert @admin.reload.active
    end

    test "admin pode rebaixar OUTRO administrador" do
      other = User.create!(email_address: "o@x.com", password: "secret123", role: :administrador)
      sign_in_as(@admin)

      patch admin_usuario_path(other), params: { role: "gestor_comercial" }

      assert other.reload.role_gestor_comercial?
    end

    test "transferência de carteira fecha a vigente e registra o autor" do
      sign_in_as(@admin)
      partner = Partner.create!(external_code: 5555, name: "CLIENTE X")
      sp2 = Salesperson.create!(external_code: 5003, nickname: "S3")
      Wallet.create!(salesperson: @sp, partner: partner, responsibility_type: :owner)

      post admin_carteiras_path, params: { partner_id: partner.id, salesperson_id: sp2.id }

      vigentes = Wallet.active.where(partner: partner)
      assert_equal 1, vigentes.count
      assert_equal sp2.id, vigentes.first.salesperson_id
      assert_equal @admin.id, vigentes.first.created_by_id
      assert_equal 1, Wallet.where(partner: partner).where.not(ends_on: nil).count # a antiga foi encerrada
    end
  end
end
