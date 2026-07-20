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
      salespeople: selectable_salespeople
    }
  end

  private

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
      potential: rec.potential_impact["revenue"].to_f, confidence: rec.confidence,
      reasons: rec.evidences, restrictions: rec.restrictions, status: rec.status,
      influenced: rec.influenced_revenues.sum(:amount).to_f
    }
  end
end
