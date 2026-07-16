# Minha Carteira (doc 08.11.3): os clientes da carteira do usuário, com o STATUS
# de risco (Engines::Risk — Sprint 6) e os sinais (recompra atrasada, inadimplência,
# queda de consumo…). Escopo: authorized_partner_ids (vendedor → sua carteira;
# gestor/admin → todas). O motor classifica só os ids autorizados — o isolamento é
# garantido pelo recorte, não pelo motor.
class WalletController < ApplicationController
  PER_PAGE = 30

  def index
    partner_ids = access.authorized_partner_ids # nil = irrestrito
    base = partner_ids.nil? ? Partner.where(id: Wallet.active.select(:partner_id)) : Partner.where(id: partner_ids)
    # Só as colunas usadas: evita materializar a coluna `raw` (jsonb pesado) de
    # milhares de parceiros no caso gestor/admin (irrestrito).
    base = base.select(:id, :name, :city, :state, :blocked)
    q = params[:q].to_s.strip
    base = base.where("partners.name ILIKE ?", "%#{q}%") if q.present?

    partners = base.to_a
    ids = partners.map(&:id)
    net12 = net_by_partner(ids)
    risk = Engines::Risk.classify_many(ids) # status + sinais + recência, em queries agregadas

    clients = partners.map do |p|
      r = risk[p.id] || {}
      {
        id: p.id, name: p.name, city: p.city, state: p.state, blocked: p.blocked,
        revenue_12m: (net12[p.id] || 0.0).round(2),
        last_purchase_on: r[:last_purchase_on], days_since: r[:days_since_purchase],
        status: r[:status]&.to_s, status_label: r[:status_label], signals: r[:signals] || [],
        repurchase_overdue: r[:repurchase_overdue].to_i
      }
    end.sort_by { |c| -c[:revenue_12m] }

    status_counts = Engines::Risk::STATUSES.index_with { |s| clients.count { |c| c[:status] == s } }
    seg = params[:status].presence
    filtered = seg ? clients.select { |c| c[:status] == seg } : clients

    page = [ params[:page].to_i, 1 ].max
    total = filtered.size
    paged = filtered.slice((page - 1) * PER_PAGE, PER_PAGE) || []

    render inertia: "Wallet", props: {
      clients: paged,
      statuses: status_counts,
      summary: {
        total: clients.size, revenue_12m: clients.sum { |c| c[:revenue_12m] }.round(2),
        repurchase_overdue: clients.count { |c| c[:repurchase_overdue].positive? }
      },
      pagination: { page: page, per: PER_PAGE, total: total, pages: (total.to_f / PER_PAGE).ceil },
      filters: { q: q.presence, status: seg }
    }
  end

  private

  # Faturamento líquido (12 meses) por parceiro — 2 queries agregadas.
  def net_by_partner(ids)
    return {} if ids.empty?

    since = 12.months.ago.to_date
    sales = Invoice.confirmed_only.sales.where(partner_id: ids, negotiation_date: since..).group(:partner_id).sum(:total_value)
    returns = Invoice.confirmed_only.returns.where(partner_id: ids, negotiation_date: since..).group(:partner_id).sum(:total_value)
    net = Hash.new(0.0)
    sales.each { |pid, v| net[pid] += v.to_f }
    returns.each { |pid, v| net[pid] -= v.to_f }
    net
  end
end
