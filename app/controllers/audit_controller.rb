# Auditoria (doc 09): gasto do agente (por dia/usuário/vendedor), syncs e alertas.
# Acesso: gestor (leitura) + admin (matriz doc 07). Coordenador e diretoria NÃO.
# Ambos os perfis são irrestritos, então a auditoria é GLOBAL (sem recorte de equipe).
class AuditController < ApplicationController
  include Exportable

  before_action :require_auditor # gestor + admin já é o perfil de exportação (doc 09)

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
      exports: report.recent_exports,
      alerts: report.alerts
    }
  end

  # CSV do gasto do agente por vendedor (custo/tokens da janela + hoje × teto).
  def export
    rows = AuditReport.new.by_seller
    headers = [ "Vendedor", "Execuções", "Custo 30d (US$)", "Tokens", "Custo hoje (US$)", "Teto diário (US$)" ]
    data = rows.map { |r| [ r[:salesperson], r[:calls], r[:cost], r[:tokens], r[:today_cost], r[:daily_cap] ] }
    send_registered_csv(kind: "custo_agente", filename: "custo-agente-#{Date.current.iso8601}.csv",
                        headers: headers, rows: data)
  end

  private

  def require_auditor
    return if Current.user&.manages_commercial? # gestor comercial + administrador

    redirect_to root_path, alert: "Acesso restrito à auditoria."
  end
end
