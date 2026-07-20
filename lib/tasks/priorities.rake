namespace :priorities do
  desc "Gera o plano do dia (priorities + recommendations) dos vendedores com carteira vigente."
  task recalc: :environment do
    n = PriorityRecalcJob.new.perform
    puts "priorização: plano do dia gerado para #{n} vendedor(es)."
  end
end
