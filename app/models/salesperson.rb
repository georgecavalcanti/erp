class Salesperson < ApplicationRecord
  has_many :invoices, dependent: :restrict_with_error

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
