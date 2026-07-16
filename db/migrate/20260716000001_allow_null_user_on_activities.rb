class AllowNullUserOnActivities < ActiveRecord::Migration[8.1]
  # Atividade é histórico (alimenta risco e receita influenciada). Ao remover um
  # usuário, preservamos suas atividades e apenas anulamos a autoria (nullify),
  # em vez de apagar o histórico junto (dependent: :destroy). Exige user_id nulável.
  def change
    change_column_null :activities, :user_id, true
  end
end
