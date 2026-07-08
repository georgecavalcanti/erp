class Company < ApplicationRecord
  has_many :invoices, dependent: :restrict_with_error

  validates :external_code, presence: true, uniqueness: true
  validates :name, presence: true

  # Localiza ou cria a empresa pelo código do ERP, mantendo o nome atualizado.
  def self.upsert_from(external_code:, name:)
    company = find_or_initialize_by(external_code: external_code)
    company.name = name if name.present?
    company.save! if company.changed?
    company
  end
end
