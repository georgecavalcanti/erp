class UniqueRecommendationPerDay < ActiveRecord::Migration[8.1]
  # Uma recomendação por (vendedor, cliente, dia) no MVP determinístico — garantia
  # dura contra duplicação, além do advisory lock em Engines::Prioritization#persist!.
  # (A Sprint 8, se o agente precisar de múltiplas, revisita esta restrição.)
  def change
    add_index :recommendations, %i[salesperson_id partner_id reference_date],
              unique: true, name: "index_recommendations_unique_per_day"
  end
end
