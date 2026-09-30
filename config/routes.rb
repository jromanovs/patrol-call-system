Rails.application.routes.draw do
  # Health check for the deployment proxy: 200 when the application boots.
  get "up" => "rails/health#show", as: :rails_health_check

  root "board#index"
  resources :calls, only: :index
  resources :guarded_sites, path: "sites", only: :index
  resources :patrol_cars, path: "cars", only: :index
  resource :map, only: :show
end
