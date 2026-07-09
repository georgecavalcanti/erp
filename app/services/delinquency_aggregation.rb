# Agrega os títulos detalhados (OverdueTitle) no resumo por vendedor (Delinquency),
# para as duas fontes de inadimplência (títulos e multi-abas) alimentarem as mesmas
# telas (Situação Geral, KPIs). Requer @batch no incluidor.
module DelinquencyAggregation
  def derive_delinquency_summary
    Delinquency.transaction do
      Delinquency.delete_all
      OverdueTitle.all.group_by(&:salesperson_label).each do |label, titles|
        salesperson = titles.find(&:salesperson_id)&.salesperson
        by_year = ->(year) { titles.select { |t| t.category_protested? && t.protest_year == year }.sum(&:amount) }
        Delinquency.create!(
          import_batch: @batch,
          salesperson: salesperson,
          salesperson_label: label,
          open_total: titles.select(&:category_open?).sum(&:amount),
          protested_2024: by_year.call(2024),
          protested_2025: by_year.call(2025),
          protested_2026: by_year.call(2026)
        )
      end
    end
  end
end
