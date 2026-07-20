module Engines
  # Classificação de risco da carteira (doc 05.3). Combina sinais determinísticos —
  # recompra atrasada, inadimplência, queda de consumo, recência de compra, tempo
  # sem contato — num status por cliente:
  #
  #   novo_em_ativacao · saudavel · em_expansao · em_atencao · em_risco · inativo
  #
  # Sem IA. Usado na tela Minha Carteira (chips) e no Cliente 360, e depois pela
  # priorização. O ESCOPO por vendedor é responsabilidade de quem chama (AccessPolicy
  # recorta os partner_ids) — o motor só classifica os ids recebidos.
  #
  #   Engines::Risk.new(partner).call                    # um parceiro
  #   Engines::Risk.classify_many(ids, as_of:)           # lote (carteira)
  class Risk
    ACTIVATION_DAYS = 90         # 1ª compra recente + poucas compras = ativando
    ACTIVATION_MAX_PURCHASES = 3
    ATTENTION_DAYS = 90          # sem comprar > 90d (e ≤ inativo) = atenção
    INACTIVE_DAYS = 180          # sem comprar > 180d = inativo
    CONTACT_GAP_DAYS = 60        # sem contato registrado > 60d = sinal

    STATUS_LABELS = {
      novo_em_ativacao: "Novo em ativação", saudavel: "Saudável", em_expansao: "Em expansão",
      em_atencao: "Em atenção", em_risco: "Em risco", inativo: "Inativo"
    }.freeze
    STATUSES = STATUS_LABELS.keys.map(&:to_s).freeze

    def initialize(partner, as_of: Date.current)
      @partner = partner
      @as_of = as_of
    end

    def call
      self.class.classify_many([ @partner.id ], as_of: @as_of)[@partner.id]
    end

    # { partner_id => { status:, status_label:, signals:[{key,label,severity}], ... } }
    # Poucas queries agregadas (não N+1), então serve a carteira inteira.
    def self.classify_many(ids, as_of: Date.current)
      ids = ids.to_a
      return {} if ids.empty?

      sales = Invoice.confirmed_only.sales.where(partner_id: ids)
      last_purchase = sales.group(:partner_id).maximum(:negotiation_date)
      first_purchase = sales.group(:partner_id).minimum(:negotiation_date)
      purchase_count = sales.group(:partner_id).count
      overdue_amount = OverdueTitle.where(partner_id: ids).group(:partner_id).sum(:amount)
      last_contact = Activity.where(partner_id: ids).group(:partner_id).maximum(:occurred_at)
      repurchase_overdue = RepurchasePrediction.overdue(as_of).where(partner_id: ids).group(:partner_id).count
      consumption = Engines::ConsumptionDrop.for_partners(ids, as_of: as_of)

      ids.index_with do |id|
        classify(
          as_of: as_of, last_purchase: last_purchase[id], first_purchase: first_purchase[id],
          purchase_count: purchase_count[id].to_i, overdue_amount: (overdue_amount[id] || 0).to_f,
          last_contact: last_contact[id], repurchase_overdue: repurchase_overdue[id].to_i,
          consumption: consumption[id]
        )
      end
    end

    # Monta os sinais e deriva o status a partir das métricas já agregadas.
    def self.classify(as_of:, last_purchase:, first_purchase:, purchase_count:, overdue_amount:,
                      last_contact:, repurchase_overdue:, consumption:)
      days_since_purchase = last_purchase ? (as_of - last_purchase).to_i : nil
      days_since_contact = last_contact ? (as_of.to_date - last_contact.to_date).to_i : nil
      dropping = consumption && consumption[:trend] == :drop
      growing = consumption && consumption[:trend] == :growth

      signals = []
      signals << signal("inadimplencia", "Inadimplência", "high") if overdue_amount.positive?
      signals << signal("recompra_atrasada", "Recompra atrasada", "medium") if repurchase_overdue.positive?
      signals << signal("queda_consumo", "Queda de consumo", "medium") if dropping
      if purchase_count.positive? && (days_since_contact.nil? || days_since_contact > CONTACT_GAP_DAYS)
        signals << signal("sem_contato", "Sem contato recente", "low")
      end
      signals << signal("expansao", "Consumo em alta", "info") if growing

      status = derive_status(
        purchase_count: purchase_count, first_purchase: first_purchase, days_since_purchase: days_since_purchase,
        overdue_amount: overdue_amount, repurchase_overdue: repurchase_overdue, dropping: dropping,
        growing: growing, as_of: as_of
      )

      {
        status: status, status_label: STATUS_LABELS[status], signals: signals,
        last_purchase_on: last_purchase, days_since_purchase: days_since_purchase,
        days_since_contact: days_since_contact, overdue_amount: overdue_amount.round(2),
        repurchase_overdue: repurchase_overdue, consumption: consumption
      }
    end

    # Precedência: ativação → inatividade → risco → atenção → expansão → saudável.
    def self.derive_status(purchase_count:, first_purchase:, days_since_purchase:, overdue_amount:,
                           repurchase_overdue:, dropping:, growing:, as_of:)
      return :novo_em_ativacao if purchase_count.zero?
      if first_purchase && (as_of - first_purchase).to_i <= ACTIVATION_DAYS && purchase_count < ACTIVATION_MAX_PURCHASES
        return :novo_em_ativacao
      end
      return :inativo if days_since_purchase && days_since_purchase > INACTIVE_DAYS
      return :em_risco if overdue_amount.positive?
      return :em_risco if dropping && repurchase_overdue.positive?
      if repurchase_overdue.positive? || dropping || (days_since_purchase && days_since_purchase > ATTENTION_DAYS)
        return :em_atencao
      end
      return :em_expansao if growing

      :saudavel
    end

    def self.signal(key, label, severity)
      { key: key, label: label, severity: severity }
    end
    private_class_method :classify, :derive_status, :signal
  end
end
