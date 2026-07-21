# Observabilidade da administração (doc 09): torna o GASTO do agente visível por
# dia/usuário/vendedor (fecha o ciclo dos tetos de custo da Sprint 8) e reúne
# sync_runs e alertas. READ-ONLY, GLOBAL — só gestor/admin acessam (matriz doc 07),
# ambos irrestritos, então não há recorte por equipe aqui.
class AuditReport
  DAYS_BACK = 30    # janela das agregações de custo
  BUSINESS_TZ = AgentRun::BUSINESS_TZ # dia/mês de negócio (BR), igual aos tetos

  def initialize(as_of: Date.current)
    @as_of = as_of
    @window_start = (as_of - DAYS_BACK.days).beginning_of_day
  end

  # Cabeçalho: gasto do MÊS × teto, gasto/tokens de HOJE × backstops, saúde geral.
  def summary
    month_cost = AgentRun.cost_spent_this_month
    monthly_budget = Agent::Config.monthly_cost_budget_usd
    {
      month_cost: month_cost.round(4),
      monthly_budget: monthly_budget,
      month_ratio: monthly_budget.positive? ? (month_cost / monthly_budget * 100).round(1) : nil,
      today_cost: AgentRun.today.sum(:cost_estimate).to_f.round(4),
      today_tokens: AgentRun.tokens_spent_today,
      daily_token_budget: Agent::Config.daily_token_budget,
      per_seller_daily_cap: Agent::Config.daily_cost_per_seller_usd,
      warning_ratio: Agent::Config.budget_warning_ratio,
      total_runs: AgentRun.count,
      error_runs: AgentRun.where.not(status: :ok).count,
      agent_enabled: Agent::Config.enabled?
    }
  end

  # Custo/tokens/execuções por DIA de negócio (últimos 30 dias) — a curva do gasto.
  def by_day
    day = business_day_sql
    AgentRun.where(created_at: @window_start..).group(day)
            .pluck(day, count_sql, cost_sql, tokens_sql, errors_sql)
            .map { |d, calls, cost, tokens, errors| day_row(d, calls, cost, tokens, errors) }
            .sort_by { |r| r[:day] }
  end

  # Gasto por USUÁRIO (quem consumiu o agente).
  def by_user
    rows = AgentRun.where(created_at: @window_start..).group(:user_id)
                   .pluck(:user_id, count_sql, cost_sql, tokens_sql, Arel.sql("MAX(created_at)"))
    names = User.where(id: rows.map(&:first)).pluck(:id, :email_address).to_h
    rows.map { |uid, calls, cost, tokens, last|
      { user: names[uid] || "—", calls: calls.to_i, cost: cost.to_f.round(4),
        tokens: tokens.to_i, last_at: last&.iso8601 }
    }.sort_by { |r| -r[:cost] }
  end

  # Gasto por VENDEDOR de contexto, com o gasto de HOJE × teto diário por vendedor.
  def by_seller
    rows = AgentRun.where(created_at: @window_start..).where.not(salesperson_id: nil)
                   .group(:salesperson_id).pluck(:salesperson_id, count_sql, cost_sql, tokens_sql)
    today = AgentRun.today.where.not(salesperson_id: nil).group(:salesperson_id).sum(:cost_estimate)
    names = Salesperson.where(id: rows.map(&:first)).pluck(:id, :nickname).to_h
    cap = Agent::Config.daily_cost_per_seller_usd
    rows.map { |sp_id, calls, cost, tokens|
      { salesperson: names[sp_id] || "—", calls: calls.to_i, cost: cost.to_f.round(4),
        tokens: tokens.to_i, today_cost: today[sp_id].to_f.round(4), daily_cap: cap }
    }.sort_by { |r| -r[:cost] }
  end

  # Ferramentas mais chamadas (janela) — nome, nº de chamadas, duração média, falhas.
  def top_tools(limit: 12)
    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT t->>'name' AS name, COUNT(*) AS calls, " \
      "ROUND(AVG(NULLIF(t->>'duration_ms', '')::numeric), 0) AS avg_ms, " \
      "COUNT(*) FILTER (WHERE (t->>'ok') = 'false') AS failures " \
      "FROM agent_runs, jsonb_array_elements(tools_called) t " \
      "WHERE created_at >= ? GROUP BY 1 ORDER BY calls DESC LIMIT ?",
      @window_start, limit
    ])
    AgentRun.connection.select_all(sql).map do |r|
      { name: r["name"], calls: r["calls"].to_i, avg_ms: r["avg_ms"].to_i, failures: r["failures"].to_i }
    end
  end

  # Execuções recentes com ferramentas chamadas e status (a trilha propriamente dita).
  def recent_runs(limit: 25)
    AgentRun.includes(:user, :salesperson).order(created_at: :desc).limit(limit).map do |run|
      {
        id: run.id, at: run.created_at.iso8601, kind: run.kind, status: run.status, model: run.model,
        user: run.user&.display_name, salesperson: run.salesperson&.nickname,
        cost: run.cost_estimate.to_f.round(4),
        tokens: run.input_tokens + run.output_tokens + run.cache_write_tokens,
        cache_read: run.cache_read_tokens, latency_ms: run.latency_ms,
        tools: Array(run.tools_called).filter_map { |t| t["name"] }
      }
    end
  end

  # Últimos syncs do Sankhya (status + erros) — trilha de integração (doc 09).
  def sync_runs(limit: 12)
    SyncRun.recent.limit(limit).map do |run|
      { at: run.finished_at.iso8601, status: run.status,
        kind: run.summary["kind"], errors: Array(run.error_messages).size }
    end
  end

  # Alertas abertos por área + os mais recentes.
  def alerts(limit: 15)
    open = Alert.open
    counts = open.group(:area).count
    {
      by_area: Alert::AREA_LABELS.map { |area, label| { area: area, label: label, count: counts[area].to_i } }
                                 .reject { |a| a[:count].zero? },
      recent: open.ranked.limit(limit).map { |a| serialize_alert(a) }
    }
  end

  private

  # Data de negócio (BR): created_at é gravado em UTC; converte p/ o fuso comercial
  # antes de truncar o dia, casando com o reset dos tetos de custo (AgentRun).
  def business_day_sql
    Arel.sql("date((agent_runs.created_at AT TIME ZONE 'UTC') AT TIME ZONE '#{BUSINESS_TZ}')")
  end

  def count_sql = Arel.sql("COUNT(*)")
  def cost_sql = Arel.sql("COALESCE(SUM(cost_estimate), 0)")
  def tokens_sql = Arel.sql("COALESCE(SUM(input_tokens + output_tokens + cache_write_tokens), 0)")
  def errors_sql = Arel.sql("COUNT(*) FILTER (WHERE status <> 0)")

  def day_row(day, calls, cost, tokens, errors)
    { day: day.to_s, calls: calls.to_i, cost: cost.to_f.round(4), tokens: tokens.to_i, errors: errors.to_i }
  end

  def serialize_alert(alert)
    {
      id: alert.id, area: alert.area, area_label: alert.area_label, severity: alert.severity,
      title: alert.title, message: alert.message, at: alert.last_detected_at.iso8601
    }
  end
end
