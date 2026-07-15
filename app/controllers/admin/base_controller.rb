module Admin
  # Base da administração comercial: exige perfil de GESTÃO (gestor comercial ou
  # administrador — ver matriz do doc 07). Carteiras e metas herdam daqui;
  # usuários apertam ainda mais (só admin) em Admin::UsersController.
  class BaseController < ApplicationController
    before_action :require_commercial_manager

    private

    def require_commercial_manager
      return if Current.user&.manages_commercial?

      redirect_to root_path, alert: "Acesso restrito à gestão comercial."
    end
  end
end
