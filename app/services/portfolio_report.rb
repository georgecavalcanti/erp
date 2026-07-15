# Consultas da carteira de pedidos pendentes (a faturar), recortadas por empresa +
# vendedor + parceiro. A DATA não recorta: a carteira é snapshot do mês corrente, um
# recorte histórico só devolveria vazio (por isso não usa Analytics#within_period).
class PortfolioReport
  def initialize(analytics = Analytics.new)
    @analytics = analytics
  end

  # Scope de PendingOrder já filtrado — público para o controller paginar a lista
  # com o mesmo recorte dos KPIs/gráficos.
  def pending_orders
    @pending_orders ||= begin
      scope = @analytics.authorize(PendingOrder.all) # recorte RBAC antes dos filtros
      scope = scope.where(company_id: @analytics.company_id) if @analytics.company_id
      scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
      scope = scope.where(partner_id: @analytics.partner_ids) if @analytics.partner_ids.any?
      scope
    end
  end

  def summary
    total = pending_orders.sum(:total_value)
    count = pending_orders.count
    {
      total: total.to_f.round(2),
      count: count,
      avg_ticket: count.zero? ? 0.0 : (total / count).to_f.round(2)
    }
  end

  def by_salesperson
    names = Salesperson.pluck(:id, :nickname).to_h
    totals = pending_orders.group(:salesperson_id).sum(:total_value)
    counts = pending_orders.group(:salesperson_id).count

    totals.map do |id, total|
      { name: id ? (names[id] || "—") : "(sem vendedor)", total: total.to_f.round(2), count: counts[id] || 0 }
    end.sort_by { |row| -row[:total] }
  end

  def by_partner(limit: 15)
    names = Partner.pluck(:id, :name).to_h
    pending_orders.group(:partner_id, :partner_name).sum(:total_value)
                  .map { |(id, raw_name), total| { name: (id && names[id]) || raw_name || "—", total: total.to_f.round(2) } }
                  .group_by { |r| r[:name] }
                  .map { |name, rows| { name: name, amount: rows.sum { |r| r[:total] }.round(2) } }
                  .sort_by { |row| -row[:amount] }.first(limit)
  end
end
