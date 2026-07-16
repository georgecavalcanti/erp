# Minha Carteira (doc 08.11.3): os clientes da carteira do usuário, com
# segmentação BÁSICA por recência de compra (status de risco só na Sprint 6).
# Escopo: authorized_partner_ids (vendedor → sua carteira; gestor/admin → todas).
class WalletController < ApplicationController
  PER_PAGE = 30
  SEGMENTS = %w[ativo atencao inativo sem_compra].freeze

  def index
    partner_ids = access.authorized_partner_ids # nil = irrestrito
    base = partner_ids.nil? ? Partner.where(id: Wallet.active.select(:partner_id)) : Partner.where(id: partner_ids)
    q = params[:q].to_s.strip
    base = base.where("partners.name ILIKE ?", "%#{q}%") if q.present?

    partners = base.to_a
    ids = partners.map(&:id)
    net12 = net_by_partner(ids)
    last_purchase = Invoice.confirmed_only.sales.where(partner_id: ids).group(:partner_id).maximum(:negotiation_date)

    clients = partners.map do |p|
      lp = last_purchase[p.id]
      days = lp ? (Date.current - lp).to_i : nil
      {
        id: p.id, name: p.name, city: p.city, state: p.state, blocked: p.blocked,
        revenue_12m: (net12[p.id] || 0.0).round(2), last_purchase_on: lp, days_since: days,
        segment: segment_for(days)
      }
    end.sort_by { |c| -c[:revenue_12m] }

    segment_counts = SEGMENTS.index_with { |s| clients.count { |c| c[:segment] == s } }
    seg = params[:segment].presence
    filtered = seg ? clients.select { |c| c[:segment] == seg } : clients

    page = [ params[:page].to_i, 1 ].max
    total = filtered.size
    paged = filtered.slice((page - 1) * PER_PAGE, PER_PAGE) || []

    render inertia: "Wallet", props: {
      clients: paged,
      segments: segment_counts,
      summary: { total: clients.size, revenue_12m: clients.sum { |c| c[:revenue_12m] }.round(2) },
      pagination: { page: page, per: PER_PAGE, total: total, pages: (total.to_f / PER_PAGE).ceil },
      filters: { q: q.presence, segment: seg }
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

  # Segmentação básica por recência (sem motor de risco — Sprint 6).
  def segment_for(days)
    return "sem_compra" if days.nil?
    return "ativo" if days <= 30
    return "atencao" if days <= 90

    "inativo"
  end
end
