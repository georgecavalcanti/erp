class DashboardController < ApplicationController
  include AnalyticsFilters

  def index
    report = analytics

    render inertia: "Dashboard", props: {
      summary: report.summary,
      delinquency: DelinquencyReport.new.summary,
      portfolio: PortfolioReport.new.summary,
      monthly: report.monthly,
      topSalespeople: report.ranking(:salesperson, limit: 8),
      topPartners: report.ranking(:partner, limit: 8),
      filters: applied_filters,
      filterOptions: filter_options
    }
  end
end
