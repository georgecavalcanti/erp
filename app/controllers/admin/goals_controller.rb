module Admin
  # Metas (gestor + admin). O ERP não gere metas (TGFMET vazia, Fase 0) → cadastro
  # é do FV360. Uma meta por (vendedor, mês, tipo). Filtra por período/vendedor.
  class GoalsController < BaseController
    before_action :set_goal, only: %i[update destroy]

    def index
      period = parse_period(params[:period]) || Date.current.beginning_of_month
      seller_id = params[:salesperson_id].presence

      scope = Goal.includes(:salesperson).for_period(period)
      scope = scope.where(salesperson_id: seller_id) if seller_id

      render inertia: "admin/Goals", props: {
        goals: scope.order("salespeople.nickname").references(:salesperson).map { |g| serialize(g) },
        filters: { period: period.strftime("%Y-%m"), salesperson_id: seller_id&.to_i },
        options: {
          salespeople: Salesperson.active.order(:nickname).pluck(:id, :nickname).map { |id, n| { id: id, name: n } },
          kinds: Goal::KINDS.keys.map { |k| { value: k, label: kind_label(k) } }
        }
      }
    end

    def create
      goal = Goal.new(goal_params.merge(created_by: Current.user))
      if goal.save
        redirect_to admin_metas_path(period: goal.period.strftime("%Y-%m")), notice: "Meta salva."
      else
        redirect_to admin_metas_path(filter_query), inertia: { errors: goal.errors }
      end
    end

    def update
      if @goal.update(goal_params)
        redirect_to admin_metas_path(period: @goal.period.strftime("%Y-%m")), notice: "Meta atualizada."
      else
        redirect_to admin_metas_path(filter_query), inertia: { errors: @goal.errors }
      end
    end

    def destroy
      period = @goal.period.strftime("%Y-%m")
      @goal.destroy
      redirect_to admin_metas_path(period: period), notice: "Meta removida."
    end

    private

    def set_goal
      @goal = Goal.find(params[:id])
    end

    def goal_params
      permitted = params.permit(:salesperson_id, :period, :kind, :amount, :min_margin_percent)
      permitted[:period] = parse_period(permitted[:period]) if permitted[:period].present?
      permitted
    end

    def filter_query
      { period: params[:period], salesperson_id: params[:salesperson_id] }.compact_blank
    end

    # Aceita "YYYY-MM" (input month do front) ou "YYYY-MM-DD"; normaliza depois.
    def parse_period(value)
      return nil if value.blank?

      str = value.to_s
      str = "#{str}-01" if str.match?(/\A\d{4}-\d{2}\z/)
      Date.parse(str)
    rescue ArgumentError, TypeError
      nil
    end

    def kind_label(kind)
      { "revenue" => "Faturamento", "margin" => "Margem", "mix" => "Mix", "activation" => "Ativação" }[kind.to_s]
    end

    def serialize(goal)
      {
        id: goal.id,
        salesperson_id: goal.salesperson_id,
        salesperson: goal.salesperson&.nickname,
        period: goal.period.strftime("%Y-%m"),
        kind: goal.kind,
        kind_label: kind_label(goal.kind),
        amount: goal.amount&.to_f,
        min_margin_percent: goal.min_margin_percent&.to_f
      }
    end
  end
end
