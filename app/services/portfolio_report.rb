# Consultas da carteira de pedidos pendentes (a faturar).
class PortfolioReport
  def summary
    scope = PendingOrder.all
    count = scope.count
    {
      total: scope.sum(:total_value).to_f.round(2),
      count: count,
      avg_ticket: count.zero? ? 0.0 : (scope.sum(:total_value) / count).to_f.round(2),
      by_delivery: scope.group(:delivery_type).sum(:total_value).transform_values { |v| v.to_f.round(2) }
    }
  end

  def by_salesperson
    names = Salesperson.pluck(:id, :nickname).to_h
    totals = PendingOrder.group(:salesperson_id).sum(:total_value)
    counts = PendingOrder.group(:salesperson_id).count

    totals.map do |id, total|
      { name: id ? (names[id] || "—") : "(sem vendedor)", total: total.to_f.round(2), count: counts[id] || 0 }
    end.sort_by { |row| -row[:total] }
  end

  def by_partner(limit: 15)
    names = Partner.pluck(:id, :name).to_h
    PendingOrder.group(:partner_id, :partner_name).sum(:total_value)
                .map { |(id, raw_name), total| { name: (id && names[id]) || raw_name || "—", total: total.to_f.round(2) } }
                .group_by { |r| r[:name] }
                .map { |name, rows| { name: name, total: rows.sum { |r| r[:total] }.round(2) } }
                .sort_by { |row| -row[:total] }.first(limit)
  end
end
