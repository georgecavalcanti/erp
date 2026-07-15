module Admin
  # Carteiras (gestor + admin). Foco no fluxo real: filtrar por vendedor, ver os
  # clientes dele, atribuir/transferir e remover. Transferência = fecha a carteira
  # vigente do parceiro (histórico preservado por ends_on) e abre a nova,
  # registrando autor e data — nunca automática, nunca pelo agente (doc 07).
  class WalletsController < BaseController
    PER_PAGE = 30

    def index
      seller_id = params[:salesperson_id].presence
      scope = Wallet.active.joins(:partner).includes(:partner, :salesperson)
      scope = scope.where(salesperson_id: seller_id) if seller_id

      page = [ params[:page].to_i, 1 ].max
      total = scope.count
      wallets = scope.order("partners.name").limit(PER_PAGE).offset((page - 1) * PER_PAGE)

      render inertia: "admin/Wallets", props: {
        wallets: wallets.map { |w| serialize(w) },
        pagination: { page: page, per: PER_PAGE, total: total, pages: (total.to_f / PER_PAGE).ceil },
        filters: { salesperson_id: seller_id&.to_i },
        options: {
          salespeople: Salesperson.active.order(:nickname).pluck(:id, :nickname).map { |id, n| { id: id, name: n } },
          responsibilities: Wallet::RESPONSIBILITY.keys.map { |k| { value: k, label: k.to_s.humanize } }
        },
        summary: { total_active: Wallet.active.count, sellers: Wallet.active.distinct.count(:salesperson_id) }
      }
    end

    # Atribui/transfere um parceiro a um vendedor. Aceita o parceiro por id (fluxo
    # de transferência a partir da lista) ou por CODPARC (adicionar novo cliente).
    def create
      partner = resolve_partner
      salesperson = Salesperson.find_by(id: params[:salesperson_id])
      return redirect_back_or_to(admin_carteiras_path, alert: "Cliente ou vendedor inválido.") unless partner && salesperson

      Wallet.transaction do
        Wallet.active.where(partner_id: partner.id).find_each(&:close!) # fecha a vigente (transferência)
        Wallet.create!(
          partner_id: partner.id, salesperson_id: salesperson.id,
          responsibility_type: params[:responsibility_type].presence || :owner,
          region: params[:region].presence, starts_on: Date.current, created_by: Current.user
        )
      end
      redirect_to admin_carteiras_path(salesperson_id: salesperson.id), notice: "Carteira atualizada."
    rescue ActiveRecord::RecordInvalid => e
      redirect_back_or_to(admin_carteiras_path, alert: e.message)
    end

    # "Remover da carteira" = encerra a vigência (ends_on), preservando o histórico.
    def destroy
      wallet = Wallet.find(params[:id])
      wallet.close!
      redirect_to admin_carteiras_path(salesperson_id: wallet.salesperson_id), notice: "Cliente removido da carteira."
    end

    private

    def resolve_partner
      Partner.find_by(id: params[:partner_id]) ||
        Partner.find_by(external_code: params[:partner_external_code].presence)
    end

    def serialize(wallet)
      {
        id: wallet.id,
        partner_id: wallet.partner_id,
        partner: wallet.partner&.name,
        partner_external_code: wallet.partner&.external_code,
        city: wallet.partner&.city,
        state: wallet.partner&.state,
        salesperson_id: wallet.salesperson_id,
        salesperson: wallet.salesperson&.nickname,
        responsibility: wallet.responsibility_type,
        region: wallet.region,
        starts_on: wallet.starts_on
      }
    end
  end
end
