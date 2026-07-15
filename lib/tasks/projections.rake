namespace :projections do
  desc "Recalcula e persiste (append-only) a projeção do mês dos vendedores com meta."
  task recalc: :environment do
    n = ProjectionRecalcJob.new.perform
    puts "projeções: #{n} vendedor(es) reprojetado(s) para #{Date.current.strftime('%m/%Y')}."
  end
end
