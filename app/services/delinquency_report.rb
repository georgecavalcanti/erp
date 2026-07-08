# Consultas de inadimplência. Sempre funciona no resumo por vendedor (Delinquency);
# quando há detalhe importado (OverdueTitle), agrega também por parceiro e por mês.
class DelinquencyReport
  def summary
    scope = Delinquency.all
    protested = scope.sum(:protested_2024) + scope.sum(:protested_2025) + scope.sum(:protested_2026)
    {
      open_total: scope.sum(:open_total).to_f.round(2),
      protested_total: protested.to_f.round(2),
      protested_by_year: {
        "2024" => scope.sum(:protested_2024).to_f.round(2),
        "2025" => scope.sum(:protested_2025).to_f.round(2),
        "2026" => scope.sum(:protested_2026).to_f.round(2)
      },
      saldo_devedor: scope.to_a.sum(&:saldo_devedor).to_f.round(2),
      salespeople_count: scope.count,
      reference_date: ImportBatch.kind_delinquency.where(status: :completed).maximum(:reference_date),
      has_detail: OverdueTitle.exists?
    }
  end

  def by_salesperson
    Delinquency.order(open_total: :desc).map do |row|
      {
        name: row.salesperson_label,
        linked: row.salesperson&.nickname,
        open: row.open_total.to_f.round(2),
        protested: row.total_protested.to_f.round(2),
        saldo: row.saldo_devedor.to_f.round(2)
      }
    end
  end

  # --- Detalhe (só quando o export detalhado foi importado) ---
  def by_partner(limit: 20)
    return [] unless OverdueTitle.exists?

    OverdueTitle.open_titles.group(:partner_name).sum(:amount)
                .sort_by { |_, v| -v }.first(limit)
                .map { |name, value| { name: name || "—", amount: value.to_f.round(2) } }
  end

  def by_due_month
    return [] unless OverdueTitle.exists?

    OverdueTitle.open_titles.where.not(due_date: nil)
                .group(Arel.sql("date_trunc('month', due_date)")).sum(:amount)
                .map { |month, value| { month: month.strftime("%Y-%m"), amount: value.to_f.round(2) } }
                .sort_by { |row| row[:month] }
  end
end
