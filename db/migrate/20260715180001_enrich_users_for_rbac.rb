class EnrichUsersForRbac < ActiveRecord::Migration[8.1]
  # RBAC (doc 07): usuário ganha PERFIL, vínculo com o vendedor do ERP e com o
  # coordenador da equipe. O isolamento de carteira (vendedor A nunca vê B) é
  # resolvido a partir de `role` + `salesperson_id` (ver AccessPolicy).
  #
  #   role: 0 vendedor · 1 representante · 2 coordenador · 3 gestor_comercial
  #         4 administrador · 5 diretoria
  #
  # Default 0 (vendedor = menor privilégio: fail-closed para linha criada sem
  # perfil explícito). Os usuários EXISTENTES (só o admin do seed) são elevados a
  # administrador no data step abaixo, para não perderem acesso.
  def up
    add_column :users, :role, :integer, null: false, default: 0
    add_column :users, :active, :boolean, null: false, default: true
    add_column :users, :name, :string
    add_reference :users, :salesperson, foreign_key: true, null: true
    add_reference :users, :manager, foreign_key: { to_table: :users }, null: true

    # Um vendedor do ERP tem no máximo um login (evita dois usuários na mesma carteira).
    add_index :users, :salesperson_id, unique: true, where: "salesperson_id IS NOT NULL",
                                       name: "index_users_unique_salesperson"

    # Preserva o acesso do admin já existente (o seed roda antes deste RBAC).
    execute "UPDATE users SET role = 4" # 4 = administrador
  end

  def down
    remove_index :users, name: "index_users_unique_salesperson"
    remove_reference :users, :manager, foreign_key: { to_table: :users }
    remove_reference :users, :salesperson, foreign_key: true
    remove_column :users, :name
    remove_column :users, :active
    remove_column :users, :role
  end
end
