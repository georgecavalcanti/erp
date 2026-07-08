namespace :sankhya do
  desc "Valida credenciais + conectividade (auth + uma query mínima em TGFEMP)"
  task smoke: :environment do
    client = Sankhya::Client.new
    env = Sankhya::Config.sandbox? ? "SANDBOX" : "PRODUÇÃO"
    puts "→ Autenticando em #{Sankhya::Config.base_url} (#{env})…"
    client.authenticate!
    puts "✓ Token obtido."

    rows = client.execute_query("SELECT CODEMP, NOMEFANTASIA FROM TSIEMP")
    puts "✓ executeQuery OK — #{rows.size} empresa(s):"
    rows.first(10).each do |r|
      puts "   #{r['CODEMP']}  #{r['NOMEFANTASIA']}"
    end
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Mapeia TOPs (venda x devolução) e amostra as notas mais recentes de TGFCAB"
  task discover: :environment do
    client = Sankhya::Client.new

    puts "== TOPs (TGFTOP) — mapear venda x devolução x pedido =="
    tops = client.execute_query(
      "SELECT CODTIPOPER, DESCROPER, TIPMOV FROM TGFTOP ORDER BY CODTIPOPER",
      allow_burst: true
    )
    tops.each { |t| puts "  #{t['CODTIPOPER']}\tTIPMOV=#{t['TIPMOV']}\t#{t['DESCROPER']}" }

    puts "\n== Amostra TGFCAB (5 maiores NUNOTA = mais recentes) =="
    sample = client.execute_query(
      "SELECT NUNOTA, NUMNOTA, CODPARC, CODVEND, CODEMP, DTNEG, DTALTER, " \
      "VLRNOTA, CODTIPOPER, TIPMOV, STATUSNOTA, PENDENTE " \
      "FROM TGFCAB ORDER BY NUNOTA DESC",
      allow_burst: true
    )
    sample.first(5).each { |r| puts "  #{r.inspect}" }
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "DRY-RUN: puxa notas (venda+devolução) dos últimos N dias e mostra o que gravaria (NÃO escreve). Ex: sankhya:invoices_dry[7]"
  task :invoices_dry, [ :days ] => :environment do |_t, args|
    days = (args[:days] || 7).to_i
    since = Date.current - days
    res = Sankhya::InvoiceSync.new(since: since).call(dry_run: true)
    puts "DRY-RUN desde #{since} — #{res[:rows]} nota(s) lidas. Amostra do que seria gravado:"
    res[:sample].each do |a|
      puts "  #{a.slice(:external_uid, :negotiation_date, :total_value, :commission, :operation_type_desc, :partner_code, :salesperson_code, :confirmed).inspect}"
    end
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sincroniza notas (venda+devolução) dos últimos N dias -> Invoice (upsert). Ex: sankhya:invoices[7]"
  task :invoices, [ :days ] => :environment do |_t, args|
    days = (args[:days] || 7).to_i
    since = Date.current - days
    res = Sankhya::InvoiceSync.new(since: since).call
    puts "Sync desde #{since}: #{res[:rows]} lidas → #{res[:imported]} novas, #{res[:updated]} atualizadas, #{res[:skipped]} puladas."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Backfill COMPLETO de notas (todo o histórico) -> Invoice (upsert, paginado)."
  task invoices_all: :environment do
    res = Sankhya::InvoiceSync.new(since: nil).call
    puts "Backfill completo: #{res[:rows]} lidas → #{res[:imported]} novas, #{res[:updated]} atualizadas, #{res[:skipped]} puladas."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sync INCREMENTAL: notas alteradas (DTALTER) nas últimas N horas -> Invoice. Ex: sankhya:invoices_incremental[2]"
  task :invoices_incremental, [ :hours ] => :environment do |_t, args|
    hours = (args[:hours] || 2).to_f
    res = Sankhya::InvoiceSync.new(changed_within_hours: hours).call
    puts "Incremental (DTALTER nas últimas #{hours}h): #{res[:rows]} lidas → #{res[:imported]} novas, #{res[:updated]} atualizadas, #{res[:skipped]} puladas."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  # APAGA os dados de fatos + dimensões para popular do zero pela API.
  # Preserva usuários. Recusa em produção por segurança.
  desc "Limpa o banco (fatos + dimensões, mantém usuários) para popular do zero. Só dev/staging."
  task reset_data: :environment do
    raise "Recusado em produção — rode só em dev/staging." if Rails.env.production?

    tables = %w[invoices pending_orders overdue_titles delinquencies partners salespeople companies import_batches]
    ActiveRecord::Base.connection.execute("TRUNCATE #{tables.join(', ')} RESTART IDENTITY")
    puts "Banco limpo: #{tables.join(', ')} (usuários preservados)."
  end

  desc "DRY-RUN carteira (pedidos pendentes 1001 + PENDENTE='S', Jatto) — só lê"
  task portfolio_dry: :environment do
    res = Sankhya::PendingOrderSync.new.call(dry_run: true)
    puts "DRY-RUN carteira: #{res[:rows]} pedidos, total R$ #{res[:total]}. Amostra:"
    res[:sample].each { |a| puts "  #{a.inspect}" }
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sincroniza a carteira (pedidos pendentes) -> PendingOrder (snapshot)."
  task portfolio: :environment do
    res = Sankhya::PendingOrderSync.new.call
    puts "Carteira sincronizada: #{res[:rows]} pedidos, total R$ #{res[:total]}."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sync agendado (cron): incremental de notas + carteira do mês. Um comando só pro Railway."
  task sync: :environment do
    # Janela de 24h no incremental cobre o intervalo noturno (o cron roda só 8h-19h),
    # garantindo que mudanças entre a última rodada do dia e a 1ª do dia seguinte não escapem.
    inv = Sankhya::InvoiceSync.new(changed_within_hours: 24).call
    puts "Notas: #{inv[:rows]} lidas → #{inv[:imported]} novas, #{inv[:updated]} atualizadas, #{inv[:skipped]} puladas."
    port = Sankhya::PendingOrderSync.new.call
    puts "Carteira: #{port[:rows]} pedidos, R$ #{port[:total]}."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end
end
