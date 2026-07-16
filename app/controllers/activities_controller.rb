# Registro rápido de atividade a partir do Cliente 360. Mesmo escopo do 360: só
# registra em cliente que o usuário pode ver (access.can_view_partner?).
class ActivitiesController < ApplicationController
  def create
    partner = Partner.find_by(id: params[:partner_id])
    unless partner && access.can_view_partner?(partner.id)
      return redirect_to root_path, alert: "Cliente fora da sua carteira."
    end

    Activity.create!(
      user: Current.user,
      partner: partner,
      salesperson: Current.user.salesperson,
      kind: params[:kind].presence || :contact,
      channel: params[:channel].presence,
      notes: params[:notes],
      occurred_at: Time.current
    )
    redirect_to cliente_path(partner), notice: "Atividade registrada."
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to cliente_path(partner), alert: "Não foi possível registrar: #{e.message}"
  end
end
