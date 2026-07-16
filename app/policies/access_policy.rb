# Escopo de autorização (RBAC, doc 07). Traduz o perfil do usuário nos ids de
# vendedor/parceiro que ele pode enxergar. É consultado pelo AnalyticsFilters
# (telas) e, no futuro, pelo tool_registry do agente — o modelo nunca decide
# escopo.
#
# Regra de ouro: um vendedor nunca vê clientes, vendas ou recomendações de outra
# carteira sem autorização explícita.
#
# Convenção de retorno de authorized_*:
#   nil  = IRRESTRITO (gestor/admin/diretoria) — não recorta
#   []   = não vê NADA (fail-closed: vendedor sem vínculo/carteira)
#   [..] = recorta exatamente a esses ids
class AccessPolicy
  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Enxerga toda a operação, sem recorte por vendedor/carteira.
  def unrestricted?
    user.nil? || user.unrestricted?
  end

  # ids de Salesperson visíveis. É o LIMITE de segurança das telas comerciais:
  # todo fato carrega salesperson_id, então recortar por ele isola A de B.
  #   vendedor/representante -> só o próprio
  #   coordenador            -> a equipe (subordinados com vínculo) + o próprio
  #   gestor/admin/diretoria -> nil (tudo)
  def authorized_salesperson_ids
    return nil if unrestricted?
    return team_salesperson_ids if user.role_coordenador?

    Array(user.salesperson_id) # nil vira [] -> fail-closed
  end

  # ids de Partner das carteiras VIGENTES dos vendedores autorizados. Usado para
  # recortar dropdowns e as telas de cliente (Sprint 5). nil = irrestrito.
  def authorized_partner_ids
    return nil if unrestricted?

    seller_ids = authorized_salesperson_ids
    return [] if seller_ids.blank?

    Wallet.active.where(salesperson_id: seller_ids).distinct.pluck(:partner_id)
  end

  # Pode abrir o Cliente 360 deste parceiro? (irrestrito vê qualquer um; vendedor
  # só os da sua carteira). É o limite de segurança das telas de cliente.
  def can_view_partner?(partner_id)
    ids = authorized_partner_ids
    ids.nil? || ids.include?(partner_id.to_i)
  end

  private

  # Coordenador: vendedores dos usuários que ele gerencia (manager_id) + o dele.
  def team_salesperson_ids
    ids = User.where(manager_id: user.id).where.not(salesperson_id: nil).pluck(:salesperson_id)
    ids << user.salesperson_id if user.salesperson_id
    ids.uniq
  end
end
