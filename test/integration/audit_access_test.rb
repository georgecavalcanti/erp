require "test_helper"

# RBAC da Auditoria (/auditoria): só gestor comercial + admin (matriz doc 07).
# Coordenador, diretoria e vendedor NÃO acessam.
class AuditAccessTest < ActionDispatch::IntegrationTest
  setup do
    @sp = Salesperson.create!(external_code: 9910, nickname: "ANA")
    @gestor = User.create!(email_address: "g@x.com", password: "secret123", role: :gestor_comercial)
    @admin = User.create!(email_address: "adm@x.com", password: "secret123", role: :administrador)
    @coord = User.create!(email_address: "c@x.com", password: "secret123", role: :coordenador)
    @diretoria = User.create!(email_address: "d@x.com", password: "secret123", role: :diretoria)
    @vendedor = User.create!(email_address: "v@x.com", password: "secret123", role: :vendedor, salesperson: @sp)
  end

  test "gestor acessa a auditoria" do
    sign_in_as(@gestor)
    get audit_path
    assert_inertia_component "Audit"
  end

  test "admin acessa a auditoria" do
    sign_in_as(@admin)
    get audit_path
    assert_inertia_component "Audit"
  end

  test "coordenador não acessa a auditoria" do
    sign_in_as(@coord)
    get audit_path
    assert_redirected_to root_path
  end

  test "diretoria não acessa a auditoria" do
    sign_in_as(@diretoria)
    get audit_path
    assert_redirected_to root_path
  end

  test "vendedor não acessa a auditoria" do
    sign_in_as(@vendedor)
    get audit_path
    assert_redirected_to root_path
  end
end
