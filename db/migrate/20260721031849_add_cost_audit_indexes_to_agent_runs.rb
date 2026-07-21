# Índices para os scopes de CUSTO (tetos da Sprint 8) e para a auditoria (Sprint 9):
#   * created_at puro: AgentRun.today / this_month / tokens_spent_today e a curva
#     "custo por dia" da auditoria filtram só por created_at (os índices existentes
#     lideram por kind/user, que não servem um range puro de data).
#   * (salesperson_id, created_at): cost_spent_today_for(sp) (teto por vendedor/dia)
#     e o "gasto por vendedor" da auditoria — supera o índice só de salesperson_id.
class AddCostAuditIndexesToAgentRuns < ActiveRecord::Migration[8.1]
  def change
    add_index :agent_runs, :created_at
    add_index :agent_runs, %i[salesperson_id created_at]
    # Redundante com o composto acima (mesmo prefixo salesperson_id).
    remove_index :agent_runs, :salesperson_id, name: "index_agent_runs_on_salesperson_id"
  end
end
