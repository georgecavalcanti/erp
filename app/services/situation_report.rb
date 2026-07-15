# "Situação geral": reconcilia, por vendedor, os fatos que compartilham a dimensão
# vendedor — faturamento (venda/devolução), carteira e inadimplência.
#
# Cada fato responde só aos filtros que fazem sentido para ele:
#   * faturamento  -> todos (período/ano-meses, empresa, vendedor, parceiro);
#   * carteira     -> empresa + vendedor + parceiro (a DATA não recorta: é snapshot
#                     do mês corrente, um recorte histórico só devolveria vazio);
#   * inadimplência-> vendedor + parceiro (snapshot dos títulos em aberto, recalculado
#                     do detalhe OverdueTitle quando existe; sem ele, resumo Delinquency).
class SituationReport
  def initialize(analytics = Analytics.new)
    @analytics = analytics
  end

  def by_salesperson
    names = Salesperson.pluck(:id, :nickname).to_h
    invoices = @analytics.invoices.confirmed_only
    sales = invoices.sales.group(:salesperson_id).sum(:total_value)
    returns = invoices.returns.group(:salesperson_id).sum(:total_value)
    commission = invoices.group(:salesperson_id).sum(:commission)
    portfolio = portfolio_scope.group(:salesperson_id).sum(:total_value)
    delinq = delinquency_by_id

    ids = (sales.keys + returns.keys + portfolio.keys + delinq.keys).compact.uniq
    rows = ids.map do |id|
      build_row(names[id] || "—", sales[id].to_f, returns[id].to_f, commission[id].to_f, portfolio[id].to_f, delinq[id])
    end

    # Inadimplência de vendedores sem cadastro casado (só rótulo). Só quando não há
    # filtro de vendedores (aí listar "os outros" não faz sentido).
    if @analytics.salesperson_ids.empty?
      delinquency_unmatched.each { |u| rows << build_row(u[:label], 0, 0, 0, 0, u) }
    end

    rows.sort_by { |row| -row[:liquido] }
  end

  # Totais consolidados (cabeçalho da situação geral).
  def totals
    rows = by_salesperson
    %i[faturamento devolucoes liquido comissao carteira inad_aberto protestado saldo].index_with do |key|
      rows.sum { |row| row[key] }.round(2)
    end
  end

  private

  def portfolio_scope
    scope = @analytics.authorize(PendingOrder.all) # recorte RBAC antes dos filtros
    scope = scope.where(company_id: @analytics.company_id) if @analytics.company_id
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope = scope.where(partner_id: @analytics.partner_ids) if @analytics.partner_ids.any?
    scope
  end

  def delinquency_by_id
    delinquency_aggregates[:by_id]
  end

  def delinquency_unmatched
    delinquency_aggregates[:unmatched]
  end

  def delinquency_aggregates
    @delinquency_aggregates ||= OverdueTitle.exists? ? aggregates_from_titles : aggregates_from_summary
  end

  # Recalcula do detalhe (OverdueTitle) recortado por vendedor + parceiro.
  def aggregates_from_titles
    titles = filtered_titles
    protested = titles.category_protested.where(protest_year: DelinquencyReport::PROTEST_YEARS)
    {
      by_id: merge_open_protested(
        titles.category_open.where.not(salesperson_id: nil).group(:salesperson_id).sum(:amount),
        protested.where.not(salesperson_id: nil).group(:salesperson_id).sum(:amount)
      ),
      unmatched: merge_open_protested(
        titles.category_open.where(salesperson_id: nil).group(:salesperson_label).sum(:amount),
        protested.where(salesperson_id: nil).group(:salesperson_label).sum(:amount)
      ).map { |label, agg| agg.merge(label: label) }
    }
  end

  # Fallback: resumo por vendedor (Delinquency) só responde ao filtro de vendedor.
  def aggregates_from_summary
    scope = delinquency_scope
    {
      by_id: scope.where.not(salesperson_id: nil).index_by(&:salesperson_id).transform_values { |d| delinq_agg(d) },
      unmatched: scope.where(salesperson_id: nil).map { |d| delinq_agg(d).merge(label: d.salesperson_label) }
    }
  end

  # { chave => open }, { chave => protestado } -> { chave => { open:, protested:, saldo: } }
  def merge_open_protested(open_by, prot_by)
    (open_by.keys | prot_by.keys).to_h do |key|
      open = (open_by[key] || 0).to_f
      protested = (prot_by[key] || 0).to_f
      [ key, { open: open, protested: protested, saldo: open + protested } ]
    end
  end

  def delinq_agg(delinquency)
    { open: delinquency.open_total.to_f, protested: delinquency.total_protested.to_f, saldo: delinquency.saldo_devedor.to_f }
  end

  def filtered_titles
    scope = @analytics.authorize(OverdueTitle.all) # recorte RBAC antes dos filtros
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope = scope.where(partner_id: @analytics.partner_ids) if @analytics.partner_ids.any?
    scope
  end

  def delinquency_scope
    scope = @analytics.authorize(Delinquency.all) # recorte RBAC antes dos filtros
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope
  end

  def build_row(name, sales, returns, commission, portfolio, inad)
    {
      name: name,
      faturamento: sales.round(2),
      devolucoes: returns.round(2),
      liquido: (sales - returns).round(2),
      comissao: commission.round(2),
      carteira: portfolio.round(2),
      inad_aberto: (inad ? inad[:open] : 0.0).round(2),
      protestado: (inad ? inad[:protested] : 0.0).round(2),
      saldo: (inad ? inad[:saldo] : 0.0).round(2)
    }
  end
end
