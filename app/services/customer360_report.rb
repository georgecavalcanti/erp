# Cliente 360 (doc 08.11.4): tudo a partir do ESPELHO LOCAL (deve responder em
# < 2s, sem IA). Receita/margem/ticket/frequência, mix por categoria, evolução
# mensal, financeiro (inadimplência + bloqueio — Fase 0: crédito = inadimplência
# + bloqueio, não LIMCRED), pedidos abertos e histórico de atividades.
#
# É de UM parceiro (CODPARC). Devolução entra com SINAL NEGATIVO em toda métrica
# de valor (faturamento, margem, mix, produtos) — nunca infla o líquido.
class Customer360Report
  MONTH = Arel.sql("date_trunc('month', negotiation_date)")
  CATEGORY = "COALESCE(products.category_name, 'Sem categoria')".freeze
  LOOKBACK = 12

  def initialize(partner, as_of: Date.current)
    @partner = partner
    @as_of = as_of
  end

  def identification
    owner = @partner.wallets.active.includes(:salesperson).first&.salesperson
    {
      id: @partner.id, external_code: @partner.external_code, name: @partner.name,
      cnpj: @partner.cnpj, city: @partner.city, state: @partner.state, segment: @partner.segment,
      active: @partner.active, blocked: @partner.blocked, block_reason: @partner.block_reason,
      salesperson: owner&.nickname, last_negotiation_on: @partner.last_negotiation_on
    }
  end

  def summary
    sales = invoices.sales
    count = sales.count
    last_purchase = sales.maximum(:negotiation_date)
    recent = invoices.where(negotiation_date: (@as_of - LOOKBACK.months)..@as_of)
    {
      revenue_total: signed_net(invoices).to_f.round(2),
      revenue_12m: signed_net(recent).to_f.round(2),
      margin_total: signed_margin(invoices).to_f.round(2),
      margin_percent: margin_percent(invoices),
      invoice_count: count,
      avg_ticket: count.zero? ? 0.0 : (sales.sum(:total_value).to_f / count).round(2),
      last_purchase_on: last_purchase,
      days_since_last: last_purchase ? (@as_of - last_purchase).to_i : nil,
      purchases_12m: recent.sales.count,
      active_months_12m: recent.sales.distinct.count(MONTH),
      avg_interval_days: avg_interval_days(recent.sales)
    }
  end

  # Faturamento líquido e margem, mês a mês (últimos N meses, inclui meses zerados).
  # Chaves normalizadas para "YYYY-MM": date_trunc devolve Time, então casar venda,
  # devolução e margem por string evita perder a devolução num mês SEM venda.
  def monthly_evolution(months: LOOKBACK)
    since = (@as_of - (months - 1).months).beginning_of_month
    scope = invoices.where(negotiation_date: since..@as_of)
    sales = by_month(scope.sales.group(MONTH).sum(:total_value))
    returns = by_month(scope.returns.group(MONTH).sum(:total_value))
    margin_s = by_month(scope.sales.group(MONTH).sum(:margin_value))
    margin_r = by_month(scope.returns.group(MONTH).sum(:margin_value))

    (0...months).map do |i|
      ym = (since + i.months).strftime("%Y-%m")
      { month: ym,
        net: ((sales[ym] || 0) - (returns[ym] || 0)).round(2),
        margin: ((margin_s[ym] || 0) - (margin_r[ym] || 0)).round(2) }
    end
  end

  # Mix: receita LÍQUIDA por categoria (venda − devolução), com participação %.
  def mix_by_category(limit: 8)
    net = merge_net(
      sale_items.group(CATEGORY).sum("invoice_items.net_value"),
      return_items.group(CATEGORY).sum("invoice_items.net_value")
    )
    total = net.values.sum
    net.sort_by { |_, v| -v }.first(limit).map do |cat, value|
      { category: cat, revenue: value.round(2), share: total.zero? ? 0.0 : (value / total * 100).round(1) }
    end
  end

  # Produtos mais comprados (receita líquida) com o estoque disponível do snapshot
  # (rápido; o dado ao vivo por produto vem de Sankhya::LiveQueries).
  def top_products(limit: 10)
    net = merge_net(
      sale_items.where.not(product_id: nil).group("invoice_items.product_id", "products.description").sum("invoice_items.net_value"),
      return_items.where.not(product_id: nil).group("invoice_items.product_id", "products.description").sum("invoice_items.net_value")
    )
    top = net.sort_by { |_, v| -v }.first(limit)
    stock = StockLevel.where(product_id: top.map { |(pid, _desc), _v| pid }).index_by(&:product_id)
    top.map do |(_pid, desc), value|
      level = stock[_pid]
      { product: desc, revenue: value.round(2),
        available: level&.sellable&.to_f, stock_synced_at: level&.synced_at&.iso8601 }
    end
  end

  # Financeiro: inadimplência (overdue_titles) + bloqueio cadastral.
  def financial
    titles = OverdueTitle.where(partner_id: @partner.id)
    open = titles.category_open.sum(:amount).to_f
    protested = titles.category_protested.sum(:amount).to_f
    {
      blocked: @partner.blocked, block_reason: @partner.block_reason,
      overdue_open: open.round(2), overdue_protested: protested.round(2),
      overdue_total: (open + protested).round(2)
    }
  end

  def open_orders
    Order.portfolio.where(partner_id: @partner.id).order(negotiation_date: :desc).limit(20).map do |o|
      { external_uid: o.external_uid, negotiation_date: o.negotiation_date, total_value: o.total_value.to_f.round(2) }
    end
  end

  def recent_activities(limit: 15)
    @partner.activities.includes(:user).recent_first.limit(limit).map do |a|
      { id: a.id, kind: a.kind, channel: a.channel, notes: a.notes,
        occurred_at: a.occurred_at.iso8601, user: a.user&.display_name }
    end
  end

  private

  def invoices
    Invoice.confirmed_only.where(partner_id: @partner.id)
  end

  # Itens do parceiro (LEFT JOIN products p/ item sem cadastro), separados por tipo
  # para que a devolução entre com sinal negativo (via merge_net).
  def item_join
    InvoiceItem.joins(:invoice)
               .joins("LEFT JOIN products ON products.id = invoice_items.product_id")
               .where(invoices: { partner_id: @partner.id, confirmed: true })
  end

  def sale_items = item_join.where(invoices: { kind: Invoice.kinds[:sale] })
  def return_items = item_join.where(invoices: { kind: Invoice.kinds[:return] })

  # { chave => venda } − { chave => devolução } => { chave => líquido (Float) }.
  def merge_net(sales, returns)
    net = Hash.new(0.0)
    sales.each { |k, v| net[k] += v.to_f }
    returns.each { |k, v| net[k] -= v.to_f }
    net
  end

  # date_trunc devolve Time; normaliza a chave para "YYYY-MM" (Float nos valores).
  def by_month(grouped)
    grouped.each_with_object(Hash.new(0.0)) { |(k, v), h| h[k.to_date.strftime("%Y-%m")] += v.to_f }
  end

  def signed_net(scope)
    (scope.sales.sum(:total_value) - scope.returns.sum(:total_value)).to_d
  end

  def signed_margin(scope)
    (scope.sales.sum(:margin_value) - scope.returns.sum(:margin_value)).to_d
  end

  def margin_percent(scope)
    net = signed_net(scope)
    return nil if net.zero?

    (signed_margin(scope) / net * 100).to_f.round(2)
  end

  # Média de dias entre compras (datas distintas de venda) no recorte. fdiv para
  # não truncar (3 compras em 3 dias -> intervalo médio 1,5, não 1).
  def avg_interval_days(sales_scope)
    dates = sales_scope.distinct.pluck(:negotiation_date).compact.sort
    return nil if dates.size < 2

    (dates.last - dates.first).to_i.fdiv(dates.size - 1).round
  end
end
