namespace :repurchase do
  desc "Concilia e gera as previsões de recompra dos parceiros com carteira vigente (append-only)."
  task forecast: :environment do
    s = RepurchaseForecastJob.new.perform
    puts "recompra: #{s[:partners]} parceiro(s) — #{s[:created]} nova(s), " \
         "#{s[:confirmed]} confirmada(s), #{s[:missed]} perdida(s)."
  end
end
