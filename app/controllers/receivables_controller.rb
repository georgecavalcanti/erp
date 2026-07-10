# Inadimplência — a partir dos dados importados (resumo por vendedor; e detalhe
# por parceiro/mês quando o export detalhado foi importado).
class ReceivablesController < ApplicationController
  include AnalyticsFilters

  def index
    report = DelinquencyReport.new(analytics)

    render inertia: "Receivables", props: {
      summary: report.summary,
      bySalesperson: report.by_salesperson,
      byPartner: report.by_partner,
      byDueMonth: report.by_due_month,
      filters: applied_filters,
      # Só vendedores/parceiros que têm inadimplência (OverdueTitle não tem empresa).
      filterOptions: Analytics.filter_options_scoped(OverdueTitle.all, company: false)
    }
  end
end
