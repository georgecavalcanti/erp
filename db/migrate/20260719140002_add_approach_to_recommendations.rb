class AddApproachToRecommendations < ActiveRecord::Migration[8.1]
  # Abordagem comercial redigida pelo agente Claude (Sprint 8) para o card do
  # Plano do Dia: como abrir a conversa, o que oferecer e o que perguntar.
  # As recomendações determinísticas (Sprint 7) seguem válidas sem abordagem.
  def change
    add_column :recommendations, :approach, :text
  end
end
