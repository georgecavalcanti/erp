# Auditoria (doc 09): gasto do agente (por dia/usuário/vendedor), syncs e alertas.
# Acesso: gestor (leitura) + admin (matriz doc 07). Coordenador e diretoria NÃO.
# Ambos os perfis são irrestritos, então a auditoria é GLOBAL (sem recorte de equipe).
class AuditController < ApplicationController
  before_action :require_auditor

  def index
    report = AuditReport.new

    render inertia: "Audit", props: {
      summary: report.summary,
      byDay: report.by_day,
      byUser: report.by_user,
      bySeller: report.by_seller,
      topTools: report.top_tools,
      recentRuns: report.recent_runs,
      syncRuns: report.sync_runs,
      alerts: report.alerts
    }
  end

  private

  def require_auditor
    return if Current.user&.manages_commercial? # gestor comercial + administrador

    redirect_to root_path, alert: "Acesso restrito à auditoria."
  end
end
