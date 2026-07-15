class Salesperson < ApplicationRecord
  has_many :invoices, dependent: :restrict_with_error
  has_many :wallets, dependent: :destroy
  has_many :partners, through: :wallets
  has_many :goals, dependent: :destroy
  has_many :projections, dependent: :delete_all
  # Login FV360 vinculado a este vendedor do ERP (RBAC). No máximo um.
  has_one :user, dependent: :nullify

  validates :external_code, presence: true, uniqueness: true
  validates :nickname, presence: true

  scope :active, -> { where(active: true) }

  def self.upsert_from(external_code:, nickname:)
    seller = find_or_initialize_by(external_code: external_code)
    seller.nickname = nickname if nickname.present?
    seller.save! if seller.changed?
    seller
  end
end
