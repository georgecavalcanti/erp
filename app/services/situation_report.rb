# "Situação geral": reconcilia, por vendedor, os quatro fatos que compartilham a
# dimensão vendedor — faturamento (venda/devolução), carteira e inadimplência.
class SituationReport
  def by_salesperson
    names = Salesperson.pluck(:id, :nickname).to_h
    sales = Invoice.sales.group(:salesperson_id).sum(:total_value)
    returns = Invoice.returns.group(:salesperson_id).sum(:total_value)
    commission = Invoice.group(:salesperson_id).sum(:commission)
    portfolio = PendingOrder.group(:salesperson_id).sum(:total_value)
    delinq = Delinquency.where.not(salesperson_id: nil).index_by(&:salesperson_id)

    ids = (sales.keys + returns.keys + portfolio.keys + delinq.keys).compact.uniq
    rows = ids.map do |id|
      build_row(names[id] || "—", sales[id].to_f, returns[id].to_f, commission[id].to_f, portfolio[id].to_f, delinq[id])
    end

    # Inadimplência de vendedores que não casaram com um cadastro (só rótulo).
    Delinquency.where(salesperson_id: nil).find_each do |row|
      rows << build_row(row.salesperson_label, 0, 0, 0, 0, row)
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
