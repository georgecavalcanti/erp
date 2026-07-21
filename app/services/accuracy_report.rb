# Acurácia dos motores (doc 05/09) — aprendizado por comparação previsto × realizado.
# READ-ONLY sobre o espelho, escopado por AccessPolicy (equipe × tudo).
#
# PROJEÇÕES (esta unidade): para cada mês FECHADO e vendedor, compara a PRIMEIRA
# projeção persistida do mês (snapshot de início do mês — mede predição pura, não
# estimativa já quase realizada) com o realizado REAL do fim do mês (das notas):
#   * dentro da faixa? realizado ∈ [conservador, potencial] daquele snapshot;
#   * erro do cenário provável = |provável − realizado| / realizado.
#
# Só meses fechados: o mês corrente ainda não tem realizado final, então não entra.
class AccuracyReport
  MONTHS_BACK = 12 # janela de meses fechados avaliados

  def initialize(access, as_of: Date.current)
    @access = access
    @as_of = as_of
    @current_month = as_of.beginning_of_month
    @window = (@current_month - MONTHS_BACK.months)...@current_month # meses fechados
    @seller_ids = access.authorized_salesperson_ids # nil | [] | [ids]
  end

  def projections
    snapshots = early_snapshots
    return empty_result if snapshots.empty?

    seller_ids = snapshots.keys.map(&:first).uniq
    realized = realized_by_seller_month(seller_ids)
    names = Salesperson.where(id: seller_ids).pluck(:id, :nickname).to_h

    pairs = snapshots.map do |(sp_id, month), snap|
      evaluate_pair(sp_id, month, snap, realized[[ sp_id, month ]].to_f)
    end
    aggregate(pairs, names)
  end

  private

  # nil (irrestrito) → sem recorte; [] (fail-closed) → nenhum; [ids] → esses.
  def scoped(relation, key: :salesperson_id)
    return relation.none if @seller_ids == []
    return relation if @seller_ids.nil?

    relation.where(key => @seller_ids)
  end

  # PRIMEIRA projeção de cada (vendedor, mês, cenário) na janela de meses fechados —
  # DISTINCT ON ordenado por data ascendente pega o snapshot mais antigo do mês.
  #   { [salesperson_id, Date(1º do mês)] => { target:, "conservative"=>v, "likely"=>v, "potential"=>v } }
  def early_snapshots
    rows = scoped(Projection.where(reference_date: @window))
           .select("DISTINCT ON (salesperson_id, date_trunc('month', reference_date), scenario) " \
                   "salesperson_id, reference_date, scenario, value, target_value")
           .order(Arel.sql("salesperson_id, date_trunc('month', reference_date), scenario, " \
                           "reference_date ASC, created_at ASC"))
    rows.each_with_object({}) do |r, acc|
      key = [ r.salesperson_id, r.reference_date.beginning_of_month ]
      snap = (acc[key] ||= { target: r.target_value&.to_f })
      snap[r.scenario] = r.value.to_f
    end
  end

  # Realizado líquido (venda − devolução) por (vendedor, mês) na mesma janela.
  def realized_by_seller_month(ids)
    base = Invoice.confirmed_only.where(salesperson_id: ids, negotiation_date: month_window)
    month = Arel.sql("date_trunc('month', negotiation_date)")
    net = Hash.new(0.0)
    base.sales.group(:salesperson_id, month).sum(:total_value).each { |(sp, m), v| net[[ sp, m.to_date ]] += v.to_f }
    base.returns.group(:salesperson_id, month).sum(:total_value).each { |(sp, m), v| net[[ sp, m.to_date ]] -= v.to_f }
    net
  end

  # A janela de projeções é por reference_date; as notas, por negotiation_date —
  # mesmos limites de mês.
  def month_window
    (@current_month - MONTHS_BACK.months).beginning_of_month..(@current_month - 1.day).end_of_month
  end

  def evaluate_pair(sp_id, month, snap, actual)
    low = snap["conservative"]
    likely = snap["likely"]
    high = snap["potential"]
    hit = (low && high) ? actual.between?(low, high) : nil
    error = (likely && !actual.zero?) ? ((likely - actual).abs / actual * 100).round(1) : nil
    {
      salesperson_id: sp_id, month: month.strftime("%Y-%m"),
      predicted: likely&.round(2), low: low&.round(2), high: high&.round(2),
      realized: actual.round(2), hit: hit, error_percent: error
    }
  end

  def aggregate(pairs, names)
    by_seller = pairs.group_by { |p| p[:salesperson_id] }.map do |sp_id, list|
      hits = list.map { |p| p[:hit] }.compact
      errors = list.map { |p| p[:error_percent] }.compact
      {
        salesperson_id: sp_id, name: names[sp_id] || "—", pairs: list.size,
        within_band_percent: rate(hits),
        mean_abs_error_percent: mean(errors),
        last: list.max_by { |p| p[:month] }
      }
    end.sort_by { |s| s[:name] }

    { summary: summarize(pairs), by_seller: by_seller }
  end

  def summarize(pairs)
    hits = pairs.map { |p| p[:hit] }.compact
    errors = pairs.map { |p| p[:error_percent] }.compact
    {
      months_evaluated: pairs.map { |p| p[:month] }.uniq.size,
      pairs: pairs.size,
      within_band_percent: rate(hits),
      mean_abs_error_percent: mean(errors)
    }
  end

  def rate(bools)
    return nil if bools.empty?

    (bools.count(true).to_f / bools.size * 100).round(1)
  end

  def mean(values)
    return nil if values.empty?

    (values.sum / values.size).round(1)
  end

  def empty_result
    { summary: { months_evaluated: 0, pairs: 0, within_band_percent: nil, mean_abs_error_percent: nil }, by_seller: [] }
  end
end
