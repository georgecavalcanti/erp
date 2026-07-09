# Devoluções. Na amostra atual não há nenhuma, mas a tela já fica pronta:
# quando chegarem notas com "DEVOLUÇÃO" no tipo de operação, aparecem aqui.
class ReturnsController < ApplicationController
  include AnalyticsFilters

  PER_PAGE = 25

  def index
    report = analytics
    scope = report.invoices.returns

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
end
