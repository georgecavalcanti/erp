class CreateWallets < ActiveRecord::Migration[8.1]
  # Carteira (doc 04/07): vínculo vendedor↔cliente COM VIGÊNCIA. Base do
  # isolamento por parceiro (authorized_partner_ids) e das telas de carteira.
  #
  # Semeada a partir do CODVEND do parceiro no Sankhya (PartnerSync gravou em
  # partners.raw). Transferências são operação do gestor (registra created_by),
  # nunca automáticas: fecha a carteira antiga (ends_on) e abre a nova.
  #
  #   responsibility_type: 0 owner (titular) · 1 contractual (representante) · 2 temporary
  def change
    create_table :wallets do |t|
      t.references :salesperson, null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: true
      t.integer :responsibility_type, null: false, default: 0
      t.string :region
      t.date :starts_on
      t.date :ends_on # null = vigente
      t.references :created_by, foreign_key: { to_table: :users } # gestor que atribuiu
      t.timestamps
    end

    add_index :wallets, %i[salesperson_id partner_id]
    # Regra de ouro: um parceiro tem no máximo UMA carteira vigente (um dono por
    # vez). Índice parcial garante no banco — reatribuir exige fechar a anterior.
    add_index :wallets, :partner_id, unique: true, where: "ends_on IS NULL",
                                     name: "index_wallets_unique_active_partner"
  end
end
