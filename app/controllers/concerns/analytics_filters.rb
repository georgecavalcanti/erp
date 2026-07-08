# Lê os filtros da query string (período + empresa/vendedor/parceiro) e monta
# o objeto Analytics correspondente. Compartilhado entre os painéis.
module AnalyticsFilters
  extend ActiveSupport::Concern

  private

  def analytics
    Analytics.new(
      period: analytics_period,
      company_id: params[:company_id],
      salesperson_id: params[:salesperson_id],
      partner_id: params[:partner_id]
    )
  end

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

  # Filtros aplicados, ecoados ao front para manter o estado dos selects.
  def applied_filters
    {
      start: params[:start].presence,
      end: params[:end].presence,
      company_id: params[:company_id].presence&.to_i,
      salesperson_id: params[:salesperson_id].presence&.to_i,
      partner_id: params[:partner_id].presence&.to_i
    }
  end

  def filter_options
    Analytics.filter_options
  end
end
