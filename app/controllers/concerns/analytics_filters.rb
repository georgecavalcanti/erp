# Lê os filtros da query string e monta o objeto Analytics correspondente.
# Compartilhado entre os painéis.
#
# O recorte temporal tem dois modos mutuamente exclusivos: intervalo De/Até
# (start/end) OU ano + meses. O front envia só um; se ambos vierem, o intervalo
# tem precedência (ver Analytics#within_period).
module AnalyticsFilters
  extend ActiveSupport::Concern

  private

  # Memoizado: o mesmo objeto alimenta os relatórios e o #authorize dos escopos
  # de snapshot (carteira/inadimplência) nos controllers.
  def analytics
    @analytics ||= Analytics.new(
      period: analytics_period,
      year: params[:year],
      months: params[:months],
      company_id: params[:company_id],
      salesperson_ids: params[:salesperson_ids],
      partner_ids: params[:partner_ids],
      # Recorte de segurança: NUNCA vem do cliente, sempre do perfil do usuário.
      authorized_salesperson_ids: access.authorized_salesperson_ids
    )
  end

  # Intervalo de datas específico (De/Até); nil quando nenhum dos dois foi informado.
  def analytics_period
    start_date = parse_date(params[:start])
    end_date = parse_date(params[:end])
    return nil unless start_date || end_date

    (start_date || Date.new(2000, 1, 1))..(end_date || Date.new(3000, 1, 1))
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Filtros aplicados, ecoados ao front para reidratar a barra de filtros. O
  # filtro de vendedor é interseccionado com o escopo autorizado — o cliente não
  # reidrata um vendedor fora da carteira (o recorte de dados já é garantido por
  # Analytics#authorize; aqui é só coerência da UI).
  def applied_filters
    {
      start: params[:start].presence,
      end: params[:end].presence,
      year: params[:year].presence&.to_i,
      months: id_list(params[:months]).select { |m| m.between?(1, 12) },
      company_id: params[:company_id].presence&.to_i,
      salesperson_ids: authorized_salesperson_filter,
      partner_ids: id_list(params[:partner_ids])
    }
  end

  # Interseção do filtro de vendedor pedido com o que o usuário pode ver.
  def authorized_salesperson_filter
    requested = id_list(params[:salesperson_ids])
    allowed = access.authorized_salesperson_ids
    return requested if allowed.nil? # irrestrito

    requested & allowed
  end

  # Normaliza params de multi-seleção (string, array ou nil) em lista de inteiros.
  def id_list(raw)
    Array(raw).map(&:to_i).reject(&:zero?)
  end

  def filter_options
    Analytics.filter_options_for(access)
  end
end
