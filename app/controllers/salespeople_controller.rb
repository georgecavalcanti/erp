class SalespeopleController < ApplicationController
  include AnalyticsFilters

  def index
    report = analytics

    render inertia: "Salespeople", props: {
      summary: report.summary,
      ranking: report.ranking(:salesperson, limit: 100),
      evolution: report.evolution(:salesperson, limit: 8),
      filters: applied_filters,
      filterOptions: filter_options
    }
  end
end
