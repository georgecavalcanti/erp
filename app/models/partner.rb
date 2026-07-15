class Partner < ApplicationRecord
  has_many :invoices, dependent: :restrict_with_error

  validates :external_code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }

  def self.upsert_from(external_code:, name:)
    partner = find_or_initialize_by(external_code: external_code)
    partner.name = name if name.present?
    partner.save! if partner.changed?
    partner
  end
end
