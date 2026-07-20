namespace :alerts do
  desc "Reavalia as condições e sincroniza a tabela de alertas operacionais."
  task scan: :environment do
    s = Alerts::Scan.call
    puts "alertas: #{s[:firing]} disparando — #{s[:created]} novo(s), " \
         "#{s[:updated]} atualizado(s), #{s[:resolved]} resolvido(s)."
  end
end
