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

  desc "DRY-RUN inadimplência (títulos em aberto/vencidos, Boleto+PIX, Jatto) — só lê"
  task inadimplencia_dry: :environment do
    res = Sankhya::OverdueTitleSync.new.call(dry_run: true)
    puts "DRY-RUN inadimplência: #{res[:rows]} títulos, R$ #{res[:total]} (#{res[:protested]} protestados). Amostra:"
    res[:sample].each { |a| puts "  #{a.inspect}" }
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sincroniza a inadimplência -> OverdueTitle + resumo Delinquency (snapshot)."
  task inadimplencia: :environment do
    res = Sankhya::OverdueTitleSync.new.call
    puts "Inadimplência: #{res[:rows]} títulos, R$ #{res[:total]} (#{res[:protested]} protestados)."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "DRY-RUN reconcile de notas: lista órfãs (deletadas/estornadas no ERP) da janela, sem apagar. Ex: sankhya:invoices_reconcile_dry[90]"
  task :invoices_reconcile_dry, [ :days ] => :environment do |_t, args|
    days = (args[:days] || 90).to_i
    since = Date.current - days
    sync = Sankhya::InvoiceSync.new(since: since)
    sync.call(dry_run: true)
    seen = sync.seen_external_uids.map(&:to_i)
    # Guard: janela vazia = o reconcile real abortaria (não apagaria nada). Ver task abaixo.
    abort "Reconcile abortaria: a API não retornou nota na janela de #{days}d (nada seria apagado)." if seen.empty?

    orphan_uids = Invoice.where(negotiation_date: since..).pluck(:external_uid) - seen
    puts "DRY-RUN reconcile #{days}d (desde #{since}): #{seen.size} NUNOTA no ERP, #{orphan_uids.size} órfã(s) local que seriam removidas:"
    Invoice.where(external_uid: orphan_uids).order(:negotiation_date).limit(20).each do |i|
      puts "  - NUNOTA #{i.external_uid} | #{i.negotiation_date} | #{i.kind} | R$ #{i.total_value}#{' | PAGO (perde marcação!)' if i.paid?}"
    end
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Reconcile de notas: upsert da janela + remove órfãs (deletadas/estornadas no ERP), preservando paid. Ex: sankhya:invoices_reconcile[90]"
  task :invoices_reconcile, [ :days ] => :environment do |_t, args|
    days = (args[:days] || 90).to_i
    since = Date.current - days
    sync = Sankhya::InvoiceSync.new(since: since)
    res = sync.call # upsert de tudo na janela (refresca edições que o incremental perdeu)
    seen = sync.seen_external_uids.map(&:to_i)
    # Guard: se a API não trouxe NADA, NÃO apaga — evita zerar a janela por falha silenciosa.
    # (Falha de página propaga Sankhya::Error e cai no rescue ANTES de qualquer delete.)
    abort "Reconcile abortado: a API não retornou nota na janela de #{days}d. Nada foi apagado." if seen.empty?

    orphan_uids = Invoice.where(negotiation_date: since..).pluck(:external_uid) - seen
    removed = orphan_uids.any? ? Invoice.where(external_uid: orphan_uids).delete_all : 0
    puts "Reconcile #{days}d (desde #{since}): #{res[:rows]} lidas → #{res[:imported]} novas, #{res[:updated]} atualizadas; #{removed} órfã(s) removida(s)."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end

  desc "Sync agendado (cron): incremental de notas + carteira + inadimplência. Resiliente (uma falha não derruba as outras) + advisory lock contra runs sobrepostos."
  task sync: :environment do
    conn = ActiveRecord::Base.connection
    lock_key = 84_720_001 # id arbitrário do advisory lock deste job
    unless conn.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      warn "sync: outra execução em andamento (advisory lock ocupado) — pulando esta rodada."
      next
    end

    errors = []
    begin
      # Janela de 24h no incremental cobre o intervalo noturno (o cron roda só 8h-19h),
      # garantindo que mudanças entre a última rodada do dia e a 1ª do dia seguinte não escapem.
      steps = {
        "Notas" => -> {
          r = Sankhya::InvoiceSync.new(changed_within_hours: 24).call
          "#{r[:rows]} lidas → #{r[:imported]} novas, #{r[:updated]} atualizadas, #{r[:skipped]} puladas."
        },
        "Carteira" => -> {
          r = Sankhya::PendingOrderSync.new.call
          "#{r[:rows]} pedidos, R$ #{r[:total]}."
        },
        "Inadimplência" => -> {
          r = Sankhya::OverdueTitleSync.new.call
          "#{r[:rows]} títulos, R$ #{r[:total]} (#{r[:protested]} protestados)."
        }
      }
      # Cada dataset falha isolado: um erro de API nas Notas não impede Carteira/Inadimplência.
      steps.each do |label, step|
        puts "#{label}: #{step.call}"
      rescue => e
        errors << "#{label}: #{e.class} — #{e.message}"
        warn "✗ #{label} falhou (as demais seguem): #{e.message}"
      end
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{lock_key})")
    end

    unless errors.empty?
      warn "sync terminou com #{errors.size} falha(s): #{errors.join(' | ')}"
      exit 1
    end
  end

  # CUTOVER de produção: LIMPA os fatos+dimensões e repopula TUDO pela API.
  # Destrutivo — exige token explícito (protege de acidente, mesmo em prod).
  desc "CUTOVER: limpa o banco e repopula tudo (notas + carteira + inadimplência) pela API. Requer CONFIRM_PROD_WIPE=faturamento."
  task bootstrap: :environment do
    unless ENV["CONFIRM_PROD_WIPE"] == "faturamento"
      abort "RECUSADO: comando destrutivo. Rode com CONFIRM_PROD_WIPE=faturamento para confirmar."
    end

    db = ActiveRecord::Base.connection.current_database
    puts "→ Alvo: banco '#{db}' (#{Rails.env}). LIMPANDO e repopulando pela API..."
    tables = %w[invoices pending_orders overdue_titles delinquencies partners salespeople companies import_batches]
    ActiveRecord::Base.connection.execute("TRUNCATE #{tables.join(', ')} RESTART IDENTITY")
    puts "  ✓ banco limpo (usuários preservados)."

    r = Sankhya::InvoiceSync.new(since: nil).call
    puts "  ✓ notas: #{r[:rows]} lidas (#{r[:imported]} novas, #{r[:skipped]} puladas)"
    r = Sankhya::PendingOrderSync.new.call
    puts "  ✓ carteira: #{r[:rows]} pedidos (R$ #{r[:total]})"
    r = Sankhya::OverdueTitleSync.new.call
    puts "  ✓ inadimplência: #{r[:rows]} títulos (R$ #{r[:total]}, #{r[:protested]} protestados)"
    puts "✓ CUTOVER COMPLETO."
  rescue Sankhya::Error => e
    warn "✗ #{e.class}: #{e.message}"
    exit 1
  end
end
