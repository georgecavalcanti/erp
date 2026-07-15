module Admin
  # CRUD de usuários — SÓ administrador (matriz do doc 07). Não há auto-registro:
  # o admin cria/convida os vendedores e define perfil, vínculo e coordenador.
  class UsersController < BaseController
    before_action :require_admin
    before_action :set_user, only: %i[edit update destroy]

    def index
      render inertia: "admin/Users", props: {
        users: User.includes(:salesperson, :manager).order(:email_address).map { |u| serialize(u) },
        options: form_options
      }
    end

    def new
      render inertia: "admin/UserForm", props: { user: nil, options: form_options }
    end

    def create
      user = User.new(user_params)
      if user.save
        redirect_to admin_usuarios_path, notice: "Usuário criado."
      else
        redirect_to new_admin_usuario_path, inertia: { errors: user.errors }
      end
    end

    def edit
      render inertia: "admin/UserForm", props: { user: serialize(@user), options: form_options }
    end

    def update
      # Senha é opcional na edição: só troca se preenchida.
      attrs = user_params
      attrs = attrs.except(:password) if attrs[:password].blank?
      if @user.update(attrs)
        redirect_to admin_usuarios_path, notice: "Usuário atualizado."
      else
        redirect_to edit_admin_usuario_path(@user), inertia: { errors: @user.errors }
      end
    end

    def destroy
      if @user == Current.user
        redirect_to admin_usuarios_path, alert: "Você não pode remover o próprio usuário."
      else
        @user.destroy
        redirect_to admin_usuarios_path, notice: "Usuário removido."
      end
    end

    private

    def require_admin
      return if Current.user&.admin?

      redirect_to root_path, alert: "Acesso restrito ao administrador."
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.permit(:email_address, :name, :password, :role, :salesperson_id, :manager_id, :active).tap do |p|
        p[:salesperson_id] = p[:salesperson_id].presence # "" -> nil
        p[:manager_id] = p[:manager_id].presence
      end
    end

    def serialize(user)
      {
        id: user.id, email_address: user.email_address, name: user.name,
        role: user.role, role_label: user.role_label, active: user.active,
        salesperson_id: user.salesperson_id, salesperson: user.salesperson&.nickname,
        manager_id: user.manager_id, manager: user.manager&.display_name
      }
    end

    def form_options
      {
        roles: User::ROLES.keys.map { |k| { value: k, label: User::ROLE_LABELS[k.to_s] } },
        salespeople: Salesperson.active.order(:nickname).pluck(:id, :nickname).map { |id, n| { id: id, name: n } },
        # Só coordenadores/gestores podem ser "manager" de um vendedor.
        managers: User.where(role: %i[coordenador gestor_comercial]).order(:email_address)
                      .map { |u| { id: u.id, name: u.display_name } }
      }
    end
  end
end
