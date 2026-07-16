class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # RBAC (doc 07). belongs_to opcional: só vendedor/representante têm salesperson.
  belongs_to :salesperson, optional: true
  belongs_to :manager, class_name: "User", optional: true
  has_many :subordinates, class_name: "User", foreign_key: :manager_id, dependent: :nullify, inverse_of: :manager
  has_many :created_wallets, class_name: "Wallet", foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  has_many :created_goals, class_name: "Goal", foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  # Atividade é histórico (risco/receita influenciada): ao remover o usuário,
  # anula a autoria mas PRESERVA a atividade (não apaga o histórico).
  has_many :activities, dependent: :nullify

  ROLES = { vendedor: 0, representante: 1, coordenador: 2, gestor_comercial: 3, administrador: 4, diretoria: 5 }.freeze
  ROLE_LABELS = {
    "vendedor" => "Vendedor", "representante" => "Representante", "coordenador" => "Coordenador",
    "gestor_comercial" => "Gestor comercial", "administrador" => "Administrador", "diretoria" => "Diretoria"
  }.freeze
  enum :role, ROLES, prefix: :role

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  # Vendedor/representante SEM vínculo com Salesperson não têm carteira → não
  # veem nada (fail-closed). Exigir o vínculo evita esse limbo silencioso.
  validates :salesperson_id, presence: true, if: :needs_salesperson?
  validates :salesperson_id, uniqueness: true, allow_nil: true

  scope :active, -> { where(active: true) }

  # Papéis que enxergam TODA a operação (não recortam por vendedor/carteira):
  # gestor comercial, administrador e diretoria. Ver AccessPolicy.
  def unrestricted?
    role_gestor_comercial? || role_administrador? || role_diretoria?
  end

  # Perfis operacionais de carteira própria (precisam de um Salesperson).
  def needs_salesperson?
    role_vendedor? || role_representante?
  end

  # Só administrador gere usuários e integrações (matriz do doc 07).
  def admin?
    role_administrador?
  end

  # Gestor e admin definem metas e carteiras.
  def manages_commercial?
    role_gestor_comercial? || role_administrador?
  end

  def display_name
    name.presence || email_address
  end

  def role_label
    ROLE_LABELS[role]
  end
end
