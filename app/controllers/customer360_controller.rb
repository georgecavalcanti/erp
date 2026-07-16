# Cliente 360 (doc 08.11.4). Escopo: o vendedor só abre cliente da SUA carteira
# (access.can_view_partner?) — nunca o de outra carteira. Tudo do espelho local
# (< 2s, sem IA); crédito/estoque ao vivo entram por Sankhya::LiveQueries.
class Customer360Controller < ApplicationController
  def show
    partner = Partner.find_by(id: params[:id])
    unless partner && access.can_view_partner?(partner.id)
      return redirect_to fallback_path, alert: "Cliente fora da sua carteira."
    end

    report = Customer360Report.new(partner)
    render inertia: "Customer360", props: {
      identification: report.identification,
      summary: report.summary,
      monthly: report.monthly_evolution,
      mix: report.mix_by_category,
      topProducts: report.top_products,
      financial: report.financial,
      openOrders: report.open_orders,
      activities: report.recent_activities,
      activityKinds: Activity::KINDS.keys.map { |k| { value: k, label: Activity::KIND_LABELS[k.to_s] } }
    }
  end

  private

  # Vendedor volta para a Minha Carteira; demais para a home.
  def fallback_path
    Current.user&.needs_salesperson? ? wallet_path : root_path
  end
end
