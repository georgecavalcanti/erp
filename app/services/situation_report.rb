# "Situação geral": reconcilia, por vendedor, os quatro fatos que compartilham a
# dimensão vendedor — faturamento (venda/devolução), carteira e inadimplência.
#
# Recebe um Analytics para reaproveitar o recorte: faturamento e carteira aceitam
# todos os filtros; a inadimplência é um snapshot por vendedor (sem mês/parceiro),
# então responde apenas ao filtro de vendedores.
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
    delinq = delinquency_scope.where.not(salesperson_id: nil).index_by(&:salesperson_id)

    ids = (sales.keys + returns.keys + portfolio.keys + delinq.keys).compact.uniq
    rows = ids.map do |id|
      build_row(names[id] || "—", sales[id].to_f, returns[id].to_f, commission[id].to_f, portfolio[id].to_f, delinq[id])
    end

    # Inadimplência de vendedores que não casaram com um cadastro (só rótulo).
    # Só entram quando não há filtro de vendedores selecionado.
    if @analytics.salesperson_ids.empty?
      delinquency_scope.where(salesperson_id: nil).find_each do |row|
        rows << build_row(row.salesperson_label, 0, 0, 0, 0, row)
      end
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

  # Carteira recortada pelos mesmos filtros do faturamento (PendingOrder tem
  # empresa/vendedor/parceiro/data).
  def portfolio_scope
    scope = PendingOrder.all
    scope = scope.in_year(@analytics.year) if @analytics.year
    scope = scope.in_months(@analytics.months) if @analytics.months.any?
    scope = scope.where(company_id: @analytics.company_id) if @analytics.company_id
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope = scope.where(partner_id: @analytics.partner_ids) if @analytics.partner_ids.any?
    scope
  end

  # Inadimplência é snapshot por vendedor: só o filtro de vendedores se aplica.
  def delinquency_scope
    scope = Delinquency.all
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope
  end

  def build_row(name, sales, returns, commission, portfolio, delinq)
    {
      name: name,
      faturamento: sales.round(2),
      devolucoes: returns.round(2),
      liquido: (sales - returns).round(2),
      comissao: commission.round(2),
      carteira: portfolio.round(2),
      inad_aberto: delinq&.open_total.to_f.round(2),
      protestado: delinq&.total_protested.to_f.round(2),
      saldo: delinq&.saldo_devedor.to_f.round(2)
    }
  end
end
