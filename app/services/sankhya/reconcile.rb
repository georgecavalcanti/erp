module Sankhya
  # Reconcilia as notas de uma janela: upsert de tudo (refresca edições que o
  # incremental por DTALTER perdeu) + remove as ÓRFÃS — notas locais da janela
  # cujo NUNOTA não voltou do ERP (deletadas/estornadas). Preserva paid/paid_at:
  # só apaga as ausentes; as sobreviventes passam por upsert (que nunca toca paid).
  #
  # Compartilhado por lib/tasks/sankhya.rake e por SankhyaReconcileJob.
  class Reconcile
    # Janela vazia = a API não trouxe nota. NÃO apaga (evitaria zerar o período
    # por uma falha silenciosa) — sinaliza o anômalo em vez de deletar às cegas.
    class EmptyWindowError < StandardError; end

    def self.call(days: 90, dry_run: false, client: nil)
      new(days: days, client: client).call(dry_run: dry_run)
    end

    def initialize(days: 90, client: nil)
      @days = days.to_i
      @since = Date.current - @days
      @client = client # injeta em testes; nil => InvoiceSync usa o Sankhya::Client real
    end

    # => { days:, since:, read:, imported:, updated:, orphan_uids:, removed:, dry_run: }
    def call(dry_run: false)
      sync = Sankhya::InvoiceSync.new(**{ since: @since, client: @client }.compact)
      res = sync.call(dry_run: dry_run) # falha de página propaga Sankhya::Error ANTES de qualquer delete
      seen = sync.seen_external_uids.map(&:to_i)
      raise EmptyWindowError, "janela de #{@days}d não retornou nota do ERP" if seen.empty?

      orphan_uids = Invoice.where(negotiation_date: @since..).pluck(:external_uid) - seen
      removed =
        if dry_run || orphan_uids.empty?
          0
        else
          Invoice.where(external_uid: orphan_uids).delete_all
        end

      {
        days: @days, since: @since,
        read: res[:rows], imported: res[:imported], updated: res[:updated],
        orphan_uids: orphan_uids, removed: removed, dry_run: dry_run
      }
    end
  end
end
