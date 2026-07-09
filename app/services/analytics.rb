# Produz as agregações que alimentam os dashboards a partir de um recorte
# (período + empresa/vendedor/parceiro). Toda a pivotagem vive aqui, então
# adicionar novas visualizações é acrescentar métodos — não reescrever telas.
class Analytics
  MONTH_SQL = Arel.sql("date_trunc('month', negotiation_date)")

  # Expostos para quem recorta outras fontes com os mesmos filtros (ex.: Situação
  # aplica o mesmo recorte à carteira/inadimplência).
  attr_reader :year, :months, :company_id, :salesperson_ids, :partner_ids

  def initialize(period: nil, year: nil, months: nil, company_id: nil, salesperson_ids: nil, partner_ids: nil, as_of: Date.current)
    @period = period
    @year = presence(year)&.to_i
    @months = int_list(months).select { |m| m.between?(1, 12) }
    @company_id = presence(company_id)
    @salesperson_ids = int_list(salesperson_ids)
    @partner_ids = int_list(partner_ids)
    @as_of = as_of
  end

  # KPIs do topo do painel.
  def summary
    sales = base.sales
    gross = sales.sum(:total_value).to_f
    returns_total = base.returns.sum(:total_value).to_f
    count = sales.count

    {
      gross_sales: gross.round(2),
      returns_total: returns_total.round(2),
      net_revenue: (gross - returns_total).round(2),
      commission_total: base.sum(:commission).to_f.round(2),
      invoice_count: count,
      avg_ticket: count.zero? ? 0.0 : (gross / count).round(2)
    }
  end

  # Faturamento mês a mês (bruto, devoluções, líquido, comissão, nº de notas).
  def monthly
    sales = base.sales.group(MONTH_SQL).sum(:total_value)
    returns = base.returns.group(MONTH_SQL).sum(:total_value)
    commission = base.group(MONTH_SQL).sum(:commission)
    counts = base.sales.group(MONTH_SQL).count

    months = (sales.keys + returns.keys + commission.keys).uniq.sort
    months.map do |m|
      gross = (sales[m] || 0).to_f
      ret = (returns[m] || 0).to_f
      {
        month: m.strftime("%Y-%m"),
        sales: gross.round(2),
        returns: ret.round(2),
        net: (gross - ret).round(2),
        commission: (commission[m] || 0).to_f.round(2),
        count: counts[m] || 0
      }
    end
  end

  # Ranking por dimensão (:salesperson ou :partner), ordenado por líquido.
  def ranking(dimension, limit: 10)
    fk = foreign_key(dimension)
    names = names_for(dimension)

    sales = base.sales.group(fk).sum(:total_value)
    returns = base.returns.group(fk).sum(:total_value)
    counts = base.sales.group(fk).count
    commission = base.group(fk).sum(:commission)

    ids = (sales.keys + returns.keys).compact.uniq
    rows = ids.map do |id|
      gross = (sales[id] || 0).to_f
      ret = (returns[id] || 0).to_f
      {
        id: id,
        name: names[id] || "—",
        sales: gross.round(2),
        returns: ret.round(2),
        net: (gross - ret).round(2),
        commission: (commission[id] || 0).to_f.round(2),
        count: counts[id] || 0
      }
    end
    rows.sort_by { |row| -row[:net] }.first(limit)
  end

  # Evolução mês a mês (líquido) das N maiores dimensões — séries para gráfico de linha.
  def evolution(dimension, limit: 8)
    fk = foreign_key(dimension)
    names = names_for(dimension)
    top_ids = ranking(dimension, limit: limit).map { |row| row[:id] }
    months = monthly.map { |row| row[:month] }
    return { months: months, series: [] } if top_ids.empty?

    sales = base.sales.where(fk => top_ids).group(fk, MONTH_SQL).sum(:total_value)
    returns = base.returns.where(fk => top_ids).group(fk, MONTH_SQL).sum(:total_value)

    net = Hash.new(0.0)
    sales.each { |(id, m), v| net[[id, m.strftime("%Y-%m")]] += v.to_f }
    returns.each { |(id, m), v| net[[id, m.strftime("%Y-%m")]] -= v.to_f }

    series = top_ids.map do |id|
      { name: names[id] || "—", data: months.map { |ym| net[[id, ym]].round(2) } }
    end
    { months: months, series: series }
  end

  # Scope de Invoice já recortado pelos filtros — público para quem precisa
  # paginar/detalhar as notas (ex.: Devoluções), evitando duplicar o filtro.
  def invoices
    base
  end

  # Aplica o recorte temporal a um scope com negotiation_date. O intervalo De/Até
  # (period) tem precedência; sem ele, recorta por ano/meses. Público para que a
  # Situação aplique o mesmo recorte à carteira.
  def within_period(scope)
    return scope.in_period(@period) if @period

    scope = scope.in_year(@year) if @year
    scope = scope.in_months(@months) if @months.any?
    scope
  end

  # Opções para os filtros (dropdowns).
  def self.filter_options
    {
      years: Invoice.distinct.pluck(Arel.sql("EXTRACT(YEAR FROM negotiation_date)::int")).compact.sort.reverse,
      companies: Company.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },
      salespeople: Salesperson.order(:nickname).pluck(:id, :nickname).map { |id, name| { id: id, name: name } },
      partners: Partner.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    }
  end

  private

  def base
    # confirmed_only: relatórios contam só notas liberadas (STATUSNOTA='L'), como a Situação.
    scope = within_period(Invoice.confirmed_only)
    scope = scope.where(company_id: @company_id) if @company_id
    scope = scope.where(salesperson_id: @salesperson_ids) if @salesperson_ids.any?
    scope = scope.where(partner_id: @partner_ids) if @partner_ids.any?
    scope
  end

  def foreign_key(dimension)
    { salesperson: :salesperson_id, partner: :partner_id, company: :company_id }.fetch(dimension)
  end

  def names_for(dimension)
    case dimension
    when :salesperson then Salesperson.pluck(:id, :nickname).to_h
    when :partner then Partner.pluck(:id, :name).to_h
    when :company then Company.pluck(:id, :name).to_h
    end
  end

  def presence(value)
    value.presence
  end

  # Normaliza params de multi-seleção (string, array ou nil) em lista de inteiros.
  def int_list(raw)
    Array(raw).map(&:to_i).reject(&:zero?)
  end
end
