# Carteira de pedidos pendentes (a faturar).
class PortfolioController < ApplicationController
  include AnalyticsFilters

  PER_PAGE = 25

  def index
    report = PortfolioReport.new(analytics)
    page = [ params[:page].to_i, 1 ].max
    scope = report.pending_orders.includes(:salesperson, :partner).order(total_value: :desc)
    total = scope.count
    orders = scope.limit(PER_PAGE).offset((page - 1) * PER_PAGE)

    render inertia: "Portfolio", props: {
      summary: report.summary,
      bySalesperson: report.by_salesperson,
      byPartner: report.by_partner,
      orders: orders.map { |o| serialize_order(o) },
      pagination: { page: page, per: PER_PAGE, total: total, pages: (total.to_f / PER_PAGE).ceil },
      filters: applied_filters,
      # Só vendedores/parceiros/empresas que têm carteira (não a lista global).
      filterOptions: Analytics.filter_options_scoped(PendingOrder.all)
    }
  end

  private

  def serialize_order(order)
    {
      id: order.id,
      external_uid: order.external_uid,
      partner: order.partner&.name || order.partner_name,
      salesperson: order.salesperson&.nickname || order.salesperson_label,
      negotiation_date: order.negotiation_date,
      total_value: order.total_value.to_f,
      delivery_type: order.delivery_label,
      note_status: order.note_status
    }
  end
end
