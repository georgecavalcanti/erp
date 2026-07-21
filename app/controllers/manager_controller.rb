# Dashboard do Gestor (doc 08): meta × realizado × projeção da EQUIPE, desvios e
# alertas. Read-only sobre o espelho — nenhuma chamada ao ERP.
#
# Escopo: coordenador vê a equipe; gestor/admin/diretoria veem tudo; diretoria é
# somente leitura. Vendedor/representante NÃO acessam (têm o Cockpit). O recorte
# de QUAIS vendedores é do AccessPolicy (nunca do cliente).
class ManagerController < ApplicationController
  include Exportable

  before_action :require_team_view
  before_action :require_exporter, only: :export # exportar é gestor+ (doc 09)

  def index
    report = ManagerReport.new(access)
    accuracy = AccuracyReport.new(access)

    render inertia: "ManagerDashboard", props: {
      month: I18n.l(Date.current, format: "%m/%Y"),
      rows: report.team,
      totals: report.totals,
      alerts: report.alerts,
      projectionAccuracy: accuracy.projections,
      repurchaseAccuracy: accuracy.repurchases,
      recommendationStats: accuracy.recommendations,
      influencedRevenue: accuracy.influenced_revenue,
      canExport: Current.user.manages_commercial?,
      readonly: Current.user.role_diretoria?
    }
  end

  # CSV da equipe (meta × realizado × projeção). Escopo: gestor/admin são
  # irrestritos, então exporta a operação inteira.
  def export
    rows = ManagerReport.new(access).team
    headers = [ "Vendedor", "Meta", "Realizado", "Margem realizada", "Atingido %", "Esperado hoje",
                "Projeção provável", "Conservador", "Potencial", "Gap", "Status" ]
    data = rows.map do |r|
      [ r[:name], r[:target], r[:realized], r[:realized_margin], r[:attainment_percent], r[:expected_to_date],
        r[:projected_likely], r[:projected_low], r[:projected_high], r[:gap], r[:status] ]
    end
    send_registered_csv(kind: "equipe", filename: "equipe-#{Date.current.iso8601}.csv",
                        headers: headers, rows: data, filters: { month: Date.current.strftime("%Y-%m") })
  end

  private

  # Barreira de papel (doc 07): só quem enxerga equipe. Vendedor/representante caem
  # no root (o Cockpit deles). O AccessPolicy ainda recorta a equipe por dentro.
  def require_team_view
    return if Current.user&.can_view_team?

    redirect_to root_path, alert: "Acesso restrito à gestão."
  end
end
