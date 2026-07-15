class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: "Muitas tentativas. Tente novamente em alguns minutos." }

  def new
    render inertia: "auth/Login"
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))
    if user.nil?
      redirect_to new_session_path, alert: "E-mail ou senha inválidos."
    elsif !user.active?
      # Usuário desativado (offboarding) não entra, mesmo com a senha correta.
      redirect_to new_session_path, alert: "Conta inativa. Procure o administrador."
    else
      start_new_session_for user
      redirect_to after_authentication_url
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
