class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Expõe o token CSRF em cookie legível para o axios do Inertia reenviar no
  # header X-CSRF-Token (ver app/frontend/entrypoints/inertia.ts).
  after_action :set_csrf_cookie

  # Props disponíveis em todas as páginas Inertia (usuário logado + flash).
  inertia_share do
    {
      auth: {
        user: Current.user && { id: Current.user.id, email: Current.user.email_address }
      },
      flash: {
        notice: flash.notice,
        alert: flash.alert
      }
    }
  end

  private

  def set_csrf_cookie
    cookies["CSRF-TOKEN"] = { value: form_authenticity_token, same_site: :lax }
  end
end
