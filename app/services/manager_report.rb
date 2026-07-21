# Agregação da equipe para o Dashboard do Gestor (doc 08). READ-ONLY sobre o
# espelho: por vendedor, reconcilia META × REALIZADO × PROJEÇÃO do mês corrente,
# com o desvio (status) e os alertas abertos da equipe.
#
# Segurança: recebe o AccessPolicy e recorta por authorized_salesperson_ids — é
# o LIMITE de segurança, nunca um filtro do cliente.
#   nil  = irrestrito (gestor/admin/diretoria) -> vendedores com meta OU venda no mês
#   []   = fail-closed (sem escopo)            -> nada
#   [..] = equipe do coordenador               -> exatamente esses (inclui os ociosos)
#
# Performance: SET-BASED por design. Nada de Engines::Projection em loop por
# vendedor — o realizado sai de um GROUP BY nas notas e a projeção da ÚLTIMA leva
# persistida por vendedor (DISTINCT ON), casando a natureza append-only de
# `projections`. O dashboard agrega a equipe inteira, então cada consulta é uma só.
class ManagerReport
  def initialize(access, as_of: Date.current)
    @access = access
    @as_of = as_of
    @month = as_of.beginning_of_month
  end

  # Uma linha por vendedor no escopo, ordenada por realizado (quem mais faturou no topo).
  def team
    @team ||= build_team
  end

  # Consolidado do cabeçalho (soma das linhas; metas/projeções ausentes contam 0).
  def totals
    rows = team
    target = rows.sum { |r| r[:target] || 0 }.round(2)
    # Atingimento consolidado compara SÓ o realizado de quem tem meta com a meta —
    # senão o realizado de vendedores sem meta inflaria o %, dando um número falso
    # (em produção todos têm meta e isto coincide com o realizado total).
    realized_with_goal = rows.select { |r| r[:target] }.sum { |r| r[:realized] }.round(2)
    {
      count: rows.size,
      target: target,
      realized: rows.sum { |r| r[:realized] }.round(2),
      realized_margin: rows.sum { |r| r[:realized_margin] }.round(2),
      projected_likely: rows.sum { |r| r[:projected_likely] || 0 }.round(2),
      gap: rows.sum { |r| r[:gap] || 0 }.round(2),
      attainment_percent: target.positive? ? (realized_with_goal / target * 100).round(1) : nil,
      at_risk_count: rows.count { |r| %w[atencao critico].include?(r[:status]) },
      behind_pace_count: rows.count { |r| r[:behind_pace] }
    }
  end

  # Alertas abertos relevantes ao escopo (doc 09): o coordenador só vê os atados a
  # vendedores da sua equipe; o irrestrito vê todos (inclui integração/conciliação
  # sem entidade). Ordenados: abertos > severidade > recência (Alert.ranked).
  def alerts(limit: 8)
    scope = Alert.open.ranked
    ids = seller_ids
    scope = scope.where(entity_type: "Salesperson", entity_id: ids) unless ids.nil?
    scope.limit(limit).map { |a| serialize_alert(a) }
  end

  private

  # nil (irrestrito) | [] (fail-closed) | [ids] (equipe). Fonte: AccessPolicy.
  def seller_ids
    @access.authorized_salesperson_ids
  end

  def build_team
    sellers = relevant_sellers.pluck(:id, :nickname).to_h
    return [] if sellers.empty?

    ids = sellers.keys
    realized = realized_by_seller(ids)
    margins = margin_by_seller(ids)
    goals = goal_amounts(ids)
    projections = latest_projections(ids)
    days = BusinessCalendar.month_stats(@as_of)

    sellers.map do |id, name|
      build_row(id, name, realized[id].to_f, margins[id].to_f, goals[id], projections[id], days)
    end.sort_by { |row| -row[:realized] }
  end

  # Vendedores no escopo. Irrestrito: só quem tem meta OU faturamento no mês (não
  # despejar centenas de vendedores do ERP sem atividade). Coordenador: a equipe
  # inteira (mesmo quem não faturou — o gestor quer ver quem está parado).
  def relevant_sellers
    ids = seller_ids
    return Salesperson.where(id: ids).order(:nickname) unless ids.nil?

    with_goal = Goal.for_period(@month).kind_revenue.distinct.pluck(:salesperson_id)
    with_sales = Invoice.confirmed_only.for_month(@as_of).where.not(salesperson_id: nil)
                        .distinct.pluck(:salesperson_id)
    Salesperson.where(id: (with_goal + with_sales).uniq).order(:nickname)
  end

  # Realizado líquido (venda − devolução) do mês, por vendedor.
  def realized_by_seller(ids)
    signed_sum(Invoice.confirmed_only.for_month(@as_of).where(salesperson_id: ids), :total_value)
  end

  # Margem realizada com sinal (devolução reverte). SUM ignora NULL: nota sem itens
  # sincronizados não derruba o total, só não soma (mesma regra do motor).
  def margin_by_seller(ids)
    signed_sum(Invoice.confirmed_only.for_month(@as_of).where(salesperson_id: ids), :margin_value)
  end

  # venda soma, devolução subtrai -> { salesperson_id => líquido }
  def signed_sum(scope, column)
    sales = scope.sales.group(:salesperson_id).sum(column)
    returns = scope.returns.group(:salesperson_id).sum(column)
    net = Hash.new(0.0)
    sales.each { |id, v| net[id] += v.to_f }
    returns.each { |id, v| net[id] -= v.to_f }
    net
  end

  def goal_amounts(ids)
    Goal.for_period(@month).kind_revenue.where(salesperson_id: ids).pluck(:salesperson_id, :amount).to_h
  end

  # Última projeção persistida por (vendedor, cenário) no mês — DISTINCT ON pega a
  # leva mais recente. { salesperson_id => { "likely" => {value:,confidence:,target:}, ... } }
  def latest_projections(ids)
    rows = Projection
           .where(salesperson_id: ids, reference_date: @month..@as_of)
           .select("DISTINCT ON (salesperson_id, scenario) salesperson_id, scenario, value, confidence, target_value")
           .order("salesperson_id, scenario, reference_date DESC, created_at DESC")
    rows.each_with_object({}) do |r, acc|
      (acc[r.salesperson_id] ||= {})[r.scenario] =
        { value: r.value.to_f, confidence: r.confidence, target: r.target_value&.to_f }
    end
  end

  def build_row(id, name, realized, realized_margin, goal_amount, projection, days)
    target = goal_amount&.to_f || projection&.dig("likely", :target)
    likely = projection&.dig("likely", :value)
    low = projection&.dig("conservative", :value)
    high = projection&.dig("potential", :value)
    expected = expected_to_date(target, days)
    {
      salesperson_id: id,
      name: name,
      target: target&.round(2),
      realized: realized.round(2),
      realized_margin: realized_margin.round(2),
      expected_to_date: expected,
      attainment_percent: (target && target.positive? ? (realized / target * 100).round(1) : nil),
      projected_likely: likely&.round(2),
      projected_low: low&.round(2),
      projected_high: high&.round(2),
      confidence: projection&.dig("likely", :confidence),
      gap: (target ? (target - (likely || realized)).round(2) : nil),
      behind_pace: (expected ? realized < expected : false),
      status: deviation_status(realized, likely, target)
    }
  end

  # Meta esperada até hoje = meta × (dias úteis decorridos / total) — mesma régua do Cockpit.
  def expected_to_date(target, days)
    return nil unless target && target.positive? && days[:total].positive?

    (target * days[:elapsed] / days[:total]).round(2)
  end

  # Desvio pela PROJEÇÃO provável vs. meta (sem projeção, usa o realizado como piso):
  #   no_alvo  -> projeção cobre a meta
  #   atencao  -> projeção fura a meta em até 15%
  #   critico  -> projeção < 85% da meta
  #   sem_meta -> vendedor sem meta cadastrada no mês
  def deviation_status(realized, likely, target)
    return "sem_meta" if target.nil? || target.zero?

    reference = likely || realized
    return "no_alvo" if reference >= target

    (target - reference) / target >= 0.15 ? "critico" : "atencao"
  end

  def serialize_alert(alert)
    {
      id: alert.id,
      area: alert.area,
      area_label: alert.area_label,
      severity: alert.severity,
      title: alert.title,
      message: alert.message,
      at: alert.last_detected_at.iso8601
    }
  end
end
