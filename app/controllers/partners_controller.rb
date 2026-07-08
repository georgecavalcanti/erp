class PartnersController < ApplicationController
  include AnalyticsFilters

  def index
    report = analytics

    render inertia: "Partners", props: {
      summary: report.summary,
      ranking: report.ranking(:partner, limit: 100),
      evolution: report.evolution(:partner, limit: 8),
      filters: applied_filters,
      filterOptions: filter_options
    }
  end
end
