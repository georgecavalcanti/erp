# Situação geral: reconciliação por vendedor (faturamento + carteira + inadimplência).
class SituationController < ApplicationController
  def index
    report = SituationReport.new

    render inertia: "Situation", props: {
      rows: report.by_salesperson,
      totals: report.totals,
      delinquencyReference: ImportBatch.kind_delinquency.where(status: :completed).maximum(:reference_date),
      hasDelinquency: Delinquency.exists?,
      hasPortfolio: PendingOrder.exists?
    }
  end
end
