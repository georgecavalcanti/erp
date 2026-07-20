# Receita influenciada (doc 04): vínculo recomendação → nota faturada. Base do
# indicador de "receita influenciada" do piloto.
class InfluencedRevenue < ApplicationRecord
  belongs_to :recommendation
  belongs_to :invoice, optional: true

  enum :linked_by, { automatic: 0, manual: 1 }, prefix: :linked_by
end
