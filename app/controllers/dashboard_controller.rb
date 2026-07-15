class DashboardController < ApplicationController
  include AnalyticsFilters

  def index
    # Root por perfil (doc 08): vendedor/representante vão para o Cockpit; gestão
    # e diretoria mantêm o dashboard consolidado.
    return redirect_to cockpit_path if Current.user&.needs_salesperson?

    report = analytics

    render inertia: "Dashboard", props: {
      summary: report.summary,
      delinquency: DelinquencyReport.new(report).summary,
      portfolio: PortfolioReport.new(report).summary,
      monthly: report.monthly,
      topSalespeople: report.ranking(:salesperson, limit: 8),
      topPartners: report.ranking(:partner, limit: 8),
      filters: applied_filters,
      filterOptions: filter_options
    }
  end
end
