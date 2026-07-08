# Inadimplência — a partir dos dados importados (resumo por vendedor; e detalhe
# por parceiro/mês quando o export detalhado foi importado).
class ReceivablesController < ApplicationController
  def index
    report = DelinquencyReport.new

    render inertia: "Receivables", props: {
      summary: report.summary,
      bySalesperson: report.by_salesperson,
      byPartner: report.by_partner,
      byDueMonth: report.by_due_month
    }
  end
end
