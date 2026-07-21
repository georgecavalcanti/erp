Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resources :passwords, param: :token

  # Painéis (Inertia + Vue)
  root "dashboard#index"
  get "cockpit",       to: "cockpit#index",     as: :cockpit
  # "Resumo do Claude" no Cockpit (Sprint 8) — gera/atualiza o resumo do agente.
  post "cockpit/resumo", to: "cockpit#resumo",  as: :cockpit_resumo
  get "situacao",      to: "situation#index",   as: :situation
  # Dashboard do Gestor (Sprint 9) — equipe (meta × realizado × projeção), desvios
  # e alertas. Escopado pela equipe (coordenador) ou tudo (gestor/admin/diretoria).
  get "gestor",        to: "manager#index",     as: :manager
  # Auditoria (Sprint 9) — gasto do agente (dia/usuário/vendedor), syncs e alertas.
  # Só gestor comercial + administrador (matriz doc 07).
  get "auditoria",     to: "audit#index",       as: :audit
  get "vendedores",    to: "salespeople#index", as: :salespeople
  get "parceiros",     to: "partners#index",    as: :partners
  get "carteira",      to: "portfolio#index",   as: :portfolio
  get "inadimplencia", to: "receivables#index", as: :receivables
  get "devolucoes",    to: "returns#index",     as: :returns

  # Cliente 360 e Minha Carteira (Sprint 5) — escopadas pela carteira do usuário.
  get  "minha-carteira", to: "wallet#index",      as: :wallet
  get  "clientes/:id",   to: "customer360#show",  as: :cliente
  post "atividades",     to: "activities#create", as: :atividades

  # Copiloto Claude (Sprint 8) — agente com ferramentas escopadas pela carteira.
  # `perguntar` responde em SSE (progresso das ferramentas + resultado final).
  get  "copiloto",           to: "copilot#index", as: :copilot
  post "copiloto/perguntar", to: "copilot_streams#create", as: :copilot_ask

  # Plano do Dia (Sprint 7) — priorização + recomendações escopadas pela carteira.
  get   "plano-do-dia",          to: "daily_plan#index",         as: :daily_plan
  # Abordagens dos cards geradas pelo agente Claude (Sprint 8).
  post  "plano-do-dia/abordagens", to: "daily_plan#abordagens",  as: :daily_plan_abordagens
  patch "recomendacoes/:id",     to: "recommendations#update",   as: :recommendation
  post  "recomendacoes/:id/resultado", to: "recommendations#result", as: :recommendation_result

  # Administração (RBAC): usuários (só admin) · carteiras e metas (gestor + admin).
  namespace :admin do
    resources :usuarios,  controller: "users",   except: :show
    resources :carteiras, controller: "wallets",  only: %i[index create destroy]
    resources :metas,     controller: "goals",   only: %i[index create update destroy]
    # Config do motor de priorização (pesos + capacidade) — singleton.
    get   "priorizacao", to: "priority_settings#index",  as: :priorizacao
    patch "priorizacao", to: "priority_settings#update"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
