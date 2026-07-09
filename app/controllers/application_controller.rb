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
      },
      lastSync: last_sync_info
    }
  end

  private

  # Último sync do Sankhya (para o cabeçalho dos painéis). Protegido contra a
  # janela de deploy em que o código novo roda antes da migration de sync_runs.
  def last_sync_info
    run = SyncRun.last_run
    run && { at: run.finished_at.iso8601, status: run.status }
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def set_csrf_cookie
    cookies["CSRF-TOKEN"] = { value: form_authenticity_token, same_site: :lax }
  end
end
