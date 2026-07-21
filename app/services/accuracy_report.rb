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
  MONTHS_BACK = 12 # janela de meses fechados avaliados (projeções)
  REC_WINDOW_DAYS = 90 # janela recente das recomendações (comportamento atual)

  CACHE_TTL = 30.minutes # acurácia é de meses FECHADOS (histórica); TTL curto basta

  def initialize(access, as_of: Date.current, cache: Rails.cache)
    @access = access
    @as_of = as_of
    @current_month = as_of.beginning_of_month
    @window = (@current_month - MONTHS_BACK.months)...@current_month # meses fechados
    @seller_ids = access.authorized_salesperson_ids # nil | [] | [ids]
    @cache = cache
  end

  # Só meses fechados → resultado historicamente estável. Cacheado por escopo/mês
  # (TTL curto cobre backfills tardios); o dashboard reprojeta a cada 30s, então
  # evita recomputar a mesma agregação a cada auto-refresh.
  def projections
    @cache.fetch(projections_cache_key, expires_in: CACHE_TTL) { compute_projections }
  end

  # Acurácia da recompra (doc 05.2): sobre as previsões RESOLVIDAS (confirmadas ou
  # perdidas), a taxa de confirmação e o erro de valor das confirmadas (valor
  # esperado × valor real da nota). Escopo por PARCEIRO (a previsão é do cliente).
  def repurchases
    resolved = scoped_partners(RepurchasePrediction.where(status: %i[confirmed missed]))
    confirmed = resolved.status_confirmed.count
    missed = resolved.status_missed.count
    total = confirmed + missed
    errors = resolved.status_confirmed.where.not(expected_value: nil).where.not(actual_value: nil)
                     .pluck(:expected_value, :actual_value)
                     .filter_map { |exp, act| act.to_f.zero? ? nil : (exp.to_f - act.to_f).abs / act.to_f * 100 }
    {
      resolved: total,
      confirmed: confirmed,
      missed: missed,
      confirmed_percent: total.zero? ? nil : (confirmed.to_f / total * 100).round(1),
      value_error_percent: mean(errors)
    }
  end

  # Recomendações por vendedor na janela recente (90d): úteis × não úteis ×
  # descartadas + receita influenciada acumulada. Escopo por vendedor.
  def recommendations
    window = (@as_of - REC_WINDOW_DAYS.days)..@as_of
    scope = scoped(Recommendation.where(reference_date: window))
    totals = scope.group(:salesperson_id).count
    useful = scope.feedback_useful.group(:salesperson_id).count
    not_useful = scope.feedback_not_useful.group(:salesperson_id).count
    discarded = scope.status_discarded.group(:salesperson_id).count
    influenced = influenced_by_seller
    names = Salesperson.where(id: totals.keys).pluck(:id, :nickname).to_h

    by_seller = totals.keys.map do |sp_id|
      build_rec_row(sp_id, names[sp_id], totals[sp_id].to_i, useful[sp_id].to_i,
                    not_useful[sp_id].to_i, discarded[sp_id].to_i, influenced[sp_id].to_f)
    end.sort_by { |r| -r[:total] }

    { summary: rec_summary(by_seller), by_seller: by_seller }
  end

  # Receita influenciada (doc 04) — total da equipe e do mês corrente.
  def influenced_revenue
    scope = scoped_influenced(InfluencedRevenue.joins(:recommendation))
    {
      total: scope.sum(:amount).to_f.round(2),
      this_month: scope.where(influenced_revenues: { created_at: @current_month.. }).sum(:amount).to_f.round(2)
    }
  end

  private

  def compute_projections
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

  # Chave por ESCOPO (irrestrito × equipe específica) e mês corrente — equipes
  # diferentes nunca compartilham entrada. O TTL cobre backfills tardios de notas.
  def projections_cache_key
    scope = @seller_ids.nil? ? "all" : @seller_ids.sort
    [ "accuracy/projections", scope, @current_month.iso8601 ]
  end

  # nil (irrestrito) → sem recorte; [] (fail-closed) → nenhum; [ids] → esses.
  def scoped(relation, key: :salesperson_id)
    return relation.none if @seller_ids == []
    return relation if @seller_ids.nil?

    relation.where(key => @seller_ids)
  end

  # Escopo por PARCEIRO (recompra): parceiros das carteiras vigentes dos vendedores
  # autorizados (AccessPolicy). nil = irrestrito; [] = nenhum; [ids] = esses.
  def scoped_partners(relation)
    ids = @access.authorized_partner_ids
    return relation if ids.nil?
    return relation.none if ids.empty?

    relation.where(partner_id: ids)
  end

  # Escopo da receita influenciada pelo vendedor da recomendação (tabela juntada).
  def scoped_influenced(relation)
    return relation.none if @seller_ids == []
    return relation if @seller_ids.nil?

    relation.where(recommendations: { salesperson_id: @seller_ids })
  end

  def influenced_by_seller
    scoped_influenced(InfluencedRevenue.joins(:recommendation))
      .group("recommendations.salesperson_id").sum(:amount)
  end

  def build_rec_row(sp_id, name, total, useful, not_useful, discarded, influenced)
    {
      salesperson_id: sp_id, name: name || "—", total: total,
      useful: useful, not_useful: not_useful, discarded: discarded,
      useful_percent: rate_pair(useful, useful + not_useful),
      influenced_amount: influenced.round(2)
    }
  end

  def rec_summary(rows)
    useful = rows.sum { |r| r[:useful] }
    not_useful = rows.sum { |r| r[:not_useful] }
    {
      total: rows.sum { |r| r[:total] },
      useful: useful, not_useful: not_useful,
      discarded: rows.sum { |r| r[:discarded] },
      useful_percent: rate_pair(useful, useful + not_useful),
      influenced_total: rows.sum { |r| r[:influenced_amount] }.round(2)
    }
  end

  # % de `part` sobre `whole` (nil quando não há base — evita 0/0).
  def rate_pair(part, whole)
    whole.zero? ? nil : (part.to_f / whole * 100).round(1)
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
