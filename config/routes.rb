Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resources :passwords, param: :token

  # Painéis (Inertia + Vue)
  root "dashboard#index"
  get "situacao",      to: "situation#index",   as: :situation
  get "vendedores",    to: "salespeople#index", as: :salespeople
  get "parceiros",     to: "partners#index",    as: :partners
  get "carteira",      to: "portfolio#index",   as: :portfolio
  get "inadimplencia", to: "receivables#index", as: :receivables
  get "devolucoes",    to: "returns#index",     as: :returns

  # Importação de planilhas (auto-detecta o tipo)
  resources :imports, only: %i[ index create ], path: "importacoes"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
