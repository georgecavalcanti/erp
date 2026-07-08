# Devoluções. Na amostra atual não há nenhuma, mas a tela já fica pronta:
# quando chegarem notas com "DEVOLUÇÃO" no tipo de operação, aparecem aqui.
class ReturnsController < ApplicationController
  include AnalyticsFilters

  PER_PAGE = 25

  def index
    report = analytics
    scope = returns_scope

    page = [ params[:page].to_i, 1 ].max
    total = scope.count
    invoices = scope.includes(:partner, :salesperson, :company)
                    .order(negotiation_date: :desc)
                    .limit(PER_PAGE).offset((page - 1) * PER_PAGE)

    render inertia: "Returns", props: {
      summary: report.summary,
      monthly: report.monthly,
      invoices: InvoiceSerializer.collection(invoices),
      pagination: { page: page, per: PER_PAGE, total: total, pages: (total.to_f / PER_PAGE).ceil },
      filters: applied_filters,
      filterOptions: filter_options
    }
  end

  private

  def returns_scope
    scope = Invoice.returns
    scope = scope.in_period(analytics_period) if analytics_period
    scope = scope.where(company_id: params[:company_id]) if params[:company_id].present?
    scope = scope.where(salesperson_id: params[:salesperson_id]) if params[:salesperson_id].present?
    scope = scope.where(partner_id: params[:partner_id]) if params[:partner_id].present?
    scope
  end
end
