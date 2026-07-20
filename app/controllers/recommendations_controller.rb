# Ações do vendedor sobre as recomendações do Plano do Dia (Sprint 7):
#   update  → muda o status (aceitar/adiar/descartar/concluir) ou o feedback
#   result  → registra o RESULTADO (venda influenciada): cria Activity(result) +
#             InfluencedRevenue vinculando a nota, e conclui a recomendação
#
# Escopo: só age em recomendação de vendedor autorizado (mesmo limite das telas).
class RecommendationsController < ApplicationController
  before_action :load_recommendation

  STATUS_EVENTS = { "aceitar" => :accepted, "adiar" => :postponed, "descartar" => :discarded, "concluir" => :done }.freeze

  def update
    attrs = {}
    if (event = params[:event].presence)
      status = STATUS_EVENTS[event] or return redirect_back_with("Ação inválida.")
      attrs[:status] = status
      attrs[:acted_at] = Time.current
    end
    attrs[:feedback] = params[:feedback] if Recommendation.feedbacks.key?(params[:feedback].to_s)
    attrs[:feedback_notes] = params[:feedback_notes] if params.key?(:feedback_notes)

    @recommendation.update!(attrs)
    redirect_to daily_plan_path(salesperson_id: @recommendation.salesperson_id), notice: "Recomendação atualizada."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_with("Não foi possível atualizar: #{e.message}")
  end

  # Registra o resultado comercial da recomendação (MVP 11): vínculo manual com a
  # nota (por NUNOTA, se informada) + valor influenciado + atividade de resultado.
  def result
    amount = params[:amount].to_f
    return redirect_back_with("Informe um valor influenciado maior que zero.") unless amount.positive?
    if @recommendation.status_done? && @recommendation.influenced_revenues.exists?
      return redirect_back_with("Resultado já registrado para esta recomendação.")
    end

    # A nota tem de ser DO CLIENTE da recomendação — nunca vincula venda de outro
    # cliente/vendedor (integridade da receita influenciada + RBAC).
    invoice = nil
    if params[:invoice_uid].present?
      invoice = Invoice.find_by(external_uid: params[:invoice_uid], partner_id: @recommendation.partner_id)
      return redirect_back_with("Nota não encontrada para este cliente.") unless invoice
    end

    Recommendation.transaction do
      @recommendation.influenced_revenues.create!(invoice: invoice, amount: amount, linked_by: :manual)
      @recommendation.update!(status: :done, feedback: :useful, acted_at: Time.current)
      Activity.create!(
        user: Current.user, partner: @recommendation.partner, salesperson: @recommendation.salesperson,
        kind: :result, notes: params[:notes].presence || "Resultado do plano do dia",
        occurred_at: Time.current, recommendation: @recommendation
      )
    end
    redirect_to daily_plan_path(salesperson_id: @recommendation.salesperson_id), notice: "Resultado registrado."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_with("Não foi possível registrar o resultado: #{e.message}")
  end

  private

  def load_recommendation
    @recommendation = Recommendation.find_by(id: params[:id])
    return redirect_to root_path, alert: "Recomendação não encontrada." unless @recommendation
    return if authorized?(@recommendation.salesperson_id)

    redirect_to root_path, alert: "Recomendação fora do seu escopo."
  end

  # Mesmo limite de segurança das telas: nil (irrestrito) ou id na lista autorizada.
  def authorized?(salesperson_id)
    ids = access.authorized_salesperson_ids
    ids.nil? || ids.include?(salesperson_id)
  end

  def redirect_back_with(alert)
    redirect_to daily_plan_path(salesperson_id: @recommendation&.salesperson_id), alert: alert
  end
end
