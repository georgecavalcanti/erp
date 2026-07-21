# Plano do Dia (doc 08.11.5, Sprint 7): as recomendações priorizadas do vendedor,
# com motivo/potencial/restrições, e o simulador de meta. Escopo: o vendedor vê o
# SEU plano; gestor/admin podem abrir o de um vendedor autorizado (?salesperson_id).
class DailyPlanController < ApplicationController
  def index
    sp = resolve_salesperson
    unless sp
      return render inertia: "DailyPlan", props: {
        salesperson: nil, capacity: nil, recommendations: [], simulator: nil, salespeople: selectable_salespeople
      }
    end

    ensure_plan!(sp)
    recs = Recommendation.for_date(Date.current).where(salesperson_id: sp.id)
                         .where.not(status: :discarded).includes(:partner, :priority).ranked
    render inertia: "DailyPlan", props: {
      salesperson: { id: sp.id, name: sp.nickname },
      capacity: PrioritySetting.current.daily_capacity,
      channels: Recommendation::CHANNELS.keys,
      recommendations: recs.map { |r| serialize(r) },
      simulator: simulator_summary(sp),
      salespeople: selectable_salespeople,
      agentEnabled: Agent::Config.enabled?
    }
  end

  # Abordagens dos cards geradas pelo agente (Sprint 8): UMA execução para os
  # cards abertos sem abordagem — a aplicação fornece a lista (id + contexto);
  # o agente redige e a persistência revalida o dono de cada card.
  def abordagens
    # Diretoria é somente leitura (doc 07) — não dispara o agente nem escreve
    # abordagens (mesmo bloqueio do copiloto; revisão cruzada Sprint 8).
    if Current.user.role_diretoria?
      return redirect_to daily_plan_path, alert: "Perfil diretoria é somente leitura."
    end

    sp = resolve_salesperson
    return redirect_to daily_plan_path, alert: "Sem vendedor no escopo." unless sp

    recs = Recommendation.for_date(Date.current).where(salesperson_id: sp.id, status: :pending, approach: nil)
                         .includes(:partner).ranked.limit(PrioritySetting.current.daily_capacity)
    if recs.none?
      return redirect_to daily_plan_path(salesperson_id: sp.id), notice: "Todos os cards já têm abordagem."
    end

    result = Agent::Orchestrator.new(user: Current.user, salesperson: sp, kind: :daily_plan)
                                .run(approaches_prompt(recs))
    if result.degraded
      redirect_to daily_plan_path(salesperson_id: sp.id), alert: result.aviso
    else
      redirect_to daily_plan_path(salesperson_id: sp.id), notice: "Abordagens geradas pelo Claude."
    end
  end

  private

  def approaches_prompt(recs)
    lines = recs.map do |r|
      "- recommendation_id #{r.id} | cliente: #{r.partner&.name} (partner_id #{r.partner_id}) | " \
        "ação: #{r.next_action} | diagnóstico: #{r.diagnosis}"
    end
    "Para cada recomendação do meu plano de hoje listada abaixo, escreva a abordagem comercial " \
      "(2 a 3 frases: como abrir a conversa, o que oferecer e o que perguntar). Consulte as ferramentas " \
      "quando precisar de contexto do cliente. Responda com abordagens: [{recommendation_id, abordagem}] " \
      "para CADA item da lista, e recomendacoes: [].\n#{lines.join("\n")}"
  end

  # Resolve o vendedor do plano respeitando o escopo (nil=irrestrito, []=nenhum).
  def resolve_salesperson
    ids = access.authorized_salesperson_ids
    requested = params[:salesperson_id].presence&.to_i
    if ids.nil?
      Salesperson.find_by(id: requested) || default_salesperson
    elsif ids.empty?
      nil
    else
      Salesperson.find_by(id: ids.include?(requested) ? requested : ids.first)
    end
  end

  # Admin/gestor sem seleção: um vendedor com carteira (para o plano ter conteúdo).
  def default_salesperson
    Salesperson.where(id: Wallet.active.select(:salesperson_id)).order(:nickname).first
  end

  # Gera o plano do dia sob demanda se ainda não existir (dev não roda o cron).
  def ensure_plan!(salesperson)
    return if Priority.for_date(Date.current).where(salesperson_id: salesperson.id).exists?

    Engines::Prioritization.new(salesperson).persist!
  end

  def simulator_summary(salesperson)
    s = Engines::GoalSimulator.new(salesperson).call
    { gap: s[:gap], projected: s[:projected], covers_gap: s[:covers_gap],
      count: s[:count], by_origin: s[:by_origin] }
  end

  # Dropdown de vendedores só para quem é irrestrito (gestor/admin).
  def selectable_salespeople
    return nil unless access.authorized_salesperson_ids.nil?

    Salesperson.where(id: Wallet.active.select(:salesperson_id)).order(:nickname).pluck(:id, :nickname)
               .map { |id, name| { id: id, name: name } }
  end

  def serialize(rec)
    {
      id: rec.id, partner_id: rec.partner_id, partner: rec.partner&.name,
      position: rec.priority&.position, score: rec.priority&.score&.to_f,
      diagnosis: rec.diagnosis, next_action: rec.next_action, channel: rec.channel,
      # Cards do agente usam "receita" (schema PT-BR); os determinísticos, "revenue".
      potential: (rec.potential_impact["revenue"] || rec.potential_impact["receita"]).to_f,
      confidence: rec.confidence,
      reasons: tags(rec.evidences), restrictions: tags(rec.restrictions), status: rec.status,
      influenced: rec.influenced_revenues.sum(:amount).to_f,
      approach: rec.approach
    }
  end

  # Normaliza para o shape {key,label} que a tela espera: cards determinísticos
  # gravam tags; cards do agente gravam strings (evidências/restrições textuais).
  def tags(list)
    Array(list).map { |t| t.is_a?(Hash) ? t : { key: t.to_s, label: t.to_s } }
  end
end
