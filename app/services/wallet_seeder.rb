# Carga inicial de carteiras (wallets) a partir do CODVEND que o PartnerSync
# gravou em partners.raw (Fase 0: ~81% dos parceiros têm vendedor). Deriva do
# espelho local — NÃO chama o Sankhya.
#
# Idempotente: cria a carteira VIGENTE do par (vendedor, parceiro) só se o
# parceiro ainda não tem uma; nunca duplica nem reatribui (transferência é
# operação manual do gestor). A partir daqui, a gestão é pela tela de carteiras.
class WalletSeeder
  def self.call(...) = new(...).call

  # => { created:, existing:, skipped_no_vend:, skipped_no_seller: }
  def call
    created = existing = skipped_no_vend = skipped_no_seller = 0
    sellers = Salesperson.pluck(:external_code, :id).to_h        # CODVEND -> salesperson_id
    already = Wallet.active.pluck(:partner_id).to_set            # parceiros já com carteira vigente

    Partner.find_each do |partner|
      codvend = partner.raw["CODVEND"].to_i
      next (skipped_no_vend += 1) if codvend.zero?               # sem vendedor no ERP

      seller_id = sellers[codvend]
      next (skipped_no_seller += 1) if seller_id.nil?           # CODVEND sem cadastro casado

      next (existing += 1) if already.include?(partner.id)

      Wallet.create!(salesperson_id: seller_id, partner_id: partner.id,
                     responsibility_type: :owner, starts_on: Date.current)
      created += 1
    end

    { created: created, existing: existing, skipped_no_vend: skipped_no_vend, skipped_no_seller: skipped_no_seller }
  end
end
