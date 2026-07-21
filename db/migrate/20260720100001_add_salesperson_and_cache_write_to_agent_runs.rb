class AddSalespersonAndCacheWriteToAgentRuns < ActiveRecord::Migration[8.1]
  # Revisão cruzada da Sprint 8:
  # * salesperson_id — a degradação "última resposta válida" precisa ser por
  #   (usuário, tipo, VENDEDOR): gestor alternando entre vendedores não pode ver
  #   o resumo da carteira de A na tela de B.
  # * cache_write_tokens — escrita de prompt cache é cobrada (1,25×) e precisa
  #   entrar no custo estimado e no teto diário.
  def change
    add_reference :agent_runs, :salesperson, foreign_key: true
    add_column :agent_runs, :cache_write_tokens, :integer, null: false, default: 0
  end
end
