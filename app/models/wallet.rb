# Carteira (doc 04/07): vínculo vendedor↔cliente com vigência. `ends_on IS NULL`
# = carteira vigente. Base de authorized_partner_ids e das telas de carteira.
# Regra de ouro: um parceiro tem no máximo UMA carteira vigente (um dono por vez).
class Wallet < ApplicationRecord
  belongs_to :salesperson
  belongs_to :partner
  belongs_to :created_by, class_name: "User", optional: true

  RESPONSIBILITY = { owner: 0, contractual: 1, temporary: 2 }.freeze
  enum :responsibility_type, RESPONSIBILITY, prefix: :responsibility

  # Carteiras vigentes (o "de quem é este cliente AGORA").
  scope :active, -> { where(ends_on: nil) }

  # Um parceiro só pode ter uma carteira vigente. Casado com o índice parcial
  # único do banco (index_wallets_unique_active_partner) — o índice é a garantia
  # real; a validação dá o erro amigável.
  validates :partner_id, uniqueness: { conditions: -> { where(ends_on: nil) } }, if: :active?
  validate :ends_after_starts

  def active?
    ends_on.nil?
  end

  # Encerra a vigência (transferência de carteira) preservando o histórico.
  def close!(on: Date.current)
    update!(ends_on: on)
  end

  private

  def ends_after_starts
    return if ends_on.nil? || starts_on.nil?

    errors.add(:ends_on, "deve ser posterior ao início") if ends_on < starts_on
  end
end
