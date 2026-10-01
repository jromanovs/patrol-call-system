Rails.application.routes.draw do
  # Health check for the deployment proxy: 200 when the application boots.
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[ new create destroy ]
  get "captcha" => "captcha#challenge", as: :captcha_challenge
  get "auth/google_oauth2/callback" => "google_sessions#create"
  get "auth/failure" => "google_sessions#failure"

  root "board#index"
  resources :calls, only: %i[ index new create ]
  resources :guarded_sites, path: "sites", only: :index
  resources :patrol_cars, path: "cars", only: :index
  resource :map, only: :show
  resources :users, except: :show
end
