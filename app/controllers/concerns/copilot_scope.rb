# Escopo comum das telas do copiloto (página + SSE): resolve o vendedor de
# contexto respeitando o RBAC e bloqueia o perfil diretoria (matriz doc 07).
module CopilotScope
  extend ActiveSupport::Concern

  included do
    before_action :deny_diretoria
  end

  private

  # Mesmo padrão do DailyPlanController: vendedor usa o próprio; irrestrito pode
  # escolher; escopo vazio = nil (a tela explica).
  def resolve_salesperson
    ids = access.authorized_salesperson_ids
    requested = params[:salesperson_id].presence&.to_i
    if ids.nil?
      Salesperson.find_by(id: requested) ||
        Salesperson.joins(:wallets).merge(Wallet.active).distinct.order(:nickname).first
    elsif ids.empty?
      nil
    else
      Salesperson.find_by(id: ids.include?(requested) ? requested : ids.first)
    end
  end

  def selectable_salespeople
    return nil unless access.authorized_salesperson_ids.nil?

    Salesperson.where(id: Wallet.active.select(:salesperson_id)).order(:nickname).pluck(:id, :nickname)
               .map { |id, name| { id: id, name: name } }
  end

  # Cards persistidos do agente — as ações (aceitar/adiar/descartar) reusam o
  # endpoint PATCH /recomendacoes/:id da Sprint 7.
  def serialize_cards(recommendations)
    recommendations.includes(:partner).map do |r|
      {
        id: r.id, partner_id: r.partner_id, partner: r.partner&.name,
        diagnosis: r.diagnosis, recommendation: r.recommendation,
        evidences: r.evidences, impact: r.potential_impact, confidence: r.confidence,
        next_action: r.next_action, channel: r.channel, deadline: r.deadline,
        restrictions: r.restrictions, status: r.status
      }
    end
  end

  # Diretoria é somente leitura consolidada (doc 07) — sem copiloto.
  def deny_diretoria
    redirect_to root_path, alert: "O copiloto não está disponível para o perfil diretoria." if Current.user.role_diretoria?
  end
end
