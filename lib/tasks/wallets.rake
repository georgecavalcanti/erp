namespace :wallets do
  desc "Carga inicial de carteiras a partir do CODVEND dos parceiros (partners.raw). Idempotente."
  task seed: :environment do
    r = WalletSeeder.call
    puts "carteiras: #{r[:created]} criadas, #{r[:existing]} já existentes, " \
         "#{r[:skipped_no_vend]} parceiros sem CODVEND, #{r[:skipped_no_seller]} CODVEND sem vendedor casado."
  end
end
