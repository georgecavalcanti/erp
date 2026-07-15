require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "usuário inativo não entra mesmo com a senha certa" do
    inactive = User.create!(email_address: "inativo@x.com", password: "secret123",
                            role: :administrador, active: false)

    post session_path, params: { email_address: inactive.email_address, password: "secret123" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    assert_match(/inativa/i, flash[:alert])
  end

  test "desativar um usuário corta o acesso na próxima requisição" do
    user = User.create!(email_address: "ativo@x.com", password: "secret123", role: :administrador)
    sign_in_as(user)
    get root_path
    assert_response :success

    user.update!(active: false)

    get root_path
    assert_redirected_to new_session_path
  end
end
