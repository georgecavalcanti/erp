# Dashboard do Gestor (doc 08): meta × realizado × projeção da EQUIPE, desvios e
# alertas. Read-only sobre o espelho — nenhuma chamada ao ERP.
#
# Escopo: coordenador vê a equipe; gestor/admin/diretoria veem tudo; diretoria é
# somente leitura. Vendedor/representante NÃO acessam (têm o Cockpit). O recorte
# de QUAIS vendedores é do AccessPolicy (nunca do cliente).
class ManagerController < ApplicationController
  before_action :require_team_view

  def index
    report = ManagerReport.new(access)

    render inertia: "ManagerDashboard", props: {
      month: I18n.l(Date.current, format: "%m/%Y"),
      rows: report.team,
      totals: report.totals,
      alerts: report.alerts,
      projectionAccuracy: AccuracyReport.new(access).projections,
      readonly: Current.user.role_diretoria?
    }
  end

  private

  # Barreira de papel (doc 07): só quem enxerga equipe. Vendedor/representante caem
  # no root (o Cockpit deles). O AccessPolicy ainda recorta a equipe por dentro.
  def require_team_view
    return if Current.user&.can_view_team?

    redirect_to root_path, alert: "Acesso restrito à gestão."
  end
end
