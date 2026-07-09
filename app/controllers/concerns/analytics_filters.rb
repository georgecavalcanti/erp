# Lê os filtros da query string (ano + meses + empresa/vendedores/parceiros) e
# monta o objeto Analytics correspondente. Compartilhado entre os painéis.
module AnalyticsFilters
  extend ActiveSupport::Concern

  private

  def analytics
    Analytics.new(
      year: params[:year],
      months: params[:months],
      company_id: params[:company_id],
      salesperson_ids: params[:salesperson_ids],
      partner_ids: params[:partner_ids]
    )
  end

  # Filtros aplicados, ecoados ao front para reidratar a barra de filtros.
  def applied_filters
    {
      year: params[:year].presence&.to_i,
      months: id_list(params[:months]).select { |m| m.between?(1, 12) },
      company_id: params[:company_id].presence&.to_i,
      salesperson_ids: id_list(params[:salesperson_ids]),
      partner_ids: id_list(params[:partner_ids])
    }
  end

  # Normaliza params de multi-seleção (string, array ou nil) em lista de inteiros.
  def id_list(raw)
    Array(raw).map(&:to_i).reject(&:zero?)
  end

  def filter_options
    Analytics.filter_options
  end
end
