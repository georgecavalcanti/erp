# Consultas de inadimplência, recortadas por vendedor + parceiro (o período NÃO
# se aplica: é um snapshot do "agora", não histórico).
#
# Quando há detalhe por título (OverdueTitle — sempre presente na era API), tudo é
# recalculado dele, então os filtros valem para KPIs, resumo e gráficos. Sem detalhe,
# cai no resumo por vendedor (Delinquency), que só responde ao filtro de vendedor.
class DelinquencyReport
  PROTEST_YEARS = [ 2024, 2025, 2026 ].freeze # anos que o resumo (Delinquency) bucketiza

  def initialize(analytics = Analytics.new)
    @analytics = analytics
  end

  def summary
    reference = ImportBatch.kind_delinquency.where(status: :completed).maximum(:reference_date)
    return summary_from_delinquency(reference) unless detail?

    titles = filtered_titles
    by_year = titles.category_protested.where(protest_year: PROTEST_YEARS).group(:protest_year).sum(:amount)
    protested = PROTEST_YEARS.to_h { |y| [ y, (by_year[y] || 0).to_f ] }
    open_total = titles.category_open.sum(:amount).to_f
    protested_total = protested.values.sum

    {
      open_total: open_total.round(2),
      protested_total: protested_total.round(2),
      protested_by_year: PROTEST_YEARS.to_h { |y| [ y.to_s, protested[y].round(2) ] },
      saldo_devedor: (open_total + protested_total).round(2),
      salespeople_count: titles.distinct.count(:salesperson_label),
      reference_date: reference,
      has_detail: true
    }
  end

  def by_salesperson
    return delinquency_by_salesperson unless detail?

    titles = filtered_titles
    open_by = titles.category_open.group(:salesperson_label).sum(:amount)
    prot_by = titles.category_protested.where(protest_year: PROTEST_YEARS).group(:salesperson_label).sum(:amount)
    nicknames = salesperson_nicknames(titles)

    titles.distinct.pluck(:salesperson_label).map do |label|
      open = (open_by[label] || 0).to_f
      protested = (prot_by[label] || 0).to_f
      { name: label, linked: nicknames[label], open: open.round(2), protested: protested.round(2), saldo: (open + protested).round(2) }
    end.sort_by { |row| -row[:open] }
  end

  def by_partner(limit: 20)
    return [] unless detail?

    filtered_titles.category_open.group(:partner_name).sum(:amount)
                   .sort_by { |_, v| -v }.first(limit)
                   .map { |name, value| { name: name || "—", amount: value.to_f.round(2) } }
  end

  def by_due_month
    return [] unless detail?

    filtered_titles.category_open.where.not(due_date: nil)
                   .group(Arel.sql("date_trunc('month', due_date)")).sum(:amount)
                   .map { |month, value| { month: month.strftime("%Y-%m"), amount: value.to_f.round(2) } }
                   .sort_by { |row| row[:month] }
  end

  private

  def detail?
    return @detail if defined?(@detail)

    @detail = OverdueTitle.exists?
  end

  # OverdueTitle filtrado por vendedor + parceiro. Período não entra: inadimplência
  # é o conjunto de títulos vencidos em aberto AGORA, não um recorte histórico.
  def filtered_titles
    scope = OverdueTitle.all
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope = scope.where(partner_id: @analytics.partner_ids) if @analytics.partner_ids.any?
    scope
  end

  # Fallback: resumo por vendedor (Delinquency) só responde ao filtro de vendedor.
  def delinquency_scope
    scope = Delinquency.all
    scope = scope.where(salesperson_id: @analytics.salesperson_ids) if @analytics.salesperson_ids.any?
    scope
  end

  def summary_from_delinquency(reference)
    scope = delinquency_scope
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
      reference_date: reference,
      has_detail: false
    }
  end

  def delinquency_by_salesperson
    delinquency_scope.order(open_total: :desc).map do |row|
      {
        name: row.salesperson_label,
        linked: row.salesperson&.nickname,
        open: row.open_total.to_f.round(2),
        protested: row.total_protested.to_f.round(2),
        saldo: row.saldo_devedor.to_f.round(2)
      }
    end
  end

  # label do vendedor -> apelido do cadastro casado (para o "→ apelido" na tabela).
  def salesperson_nicknames(titles)
    ids_by_label = titles.where.not(salesperson_id: nil).distinct.pluck(:salesperson_label, :salesperson_id).to_h
    nicknames = Salesperson.where(id: ids_by_label.values).pluck(:id, :nickname).to_h
    ids_by_label.transform_values { |id| nicknames[id] }
  end
end
