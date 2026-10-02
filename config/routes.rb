Rails.application.routes.draw do
  # Health check for the deployment proxy: 200 when the application boots.
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[ new create destroy ]
  get "captcha" => "captcha#challenge", as: :captcha_challenge
  get "auth/google_oauth2/callback" => "google_sessions#create"
  get "auth/failure" => "google_sessions#failure"

  root "board#index"
  resource :call_cleanup, path: "calls/cleanup", only: %i[ new create ]
  resources :calls, only: %i[ index show new create edit update destroy ] do
    resource :dispatch, only: %i[ new create ]
    resource :arrival, only: :create
    resource :closing, only: %i[ new create ]
    resource :cancellation, only: %i[ new create ]
  end
  resources :guarded_sites, path: "sites"
  resources :addresses, only: :index
  resources :patrol_cars, path: "cars"
  resource :map, only: :show
  # STO-06, BR-13: the published map files, to signed-in users only, in the
  # pieces a browser asks for, as binary data (no compression of ranges); a
  # name never reused lets browsers keep each file.
  constraints(->(request) { Session.of_active_users.exists?(id: request.cookie_jar.signed[:session_id]) }) do
    mount Rack::Files.new(MapBuild::FOLDER.join("published").to_s,
                          { "cache-control" => "private, max-age=31536000, immutable" },
                          "application/octet-stream"), at: "/tiles"
  end
  resource :statistics, only: :show
  resources :users, except: :show
  resource :api_key, only: %i[ show create ]

  # 4.2: the API, with the personal API key of the user (BR-13).
  namespace :api do
    namespace :v1, defaults: { format: :json } do
      resources :sites, except: %i[ new edit ]
      resources :patrol_cars, except: %i[ new edit ]
      resources :calls, except: %i[ new edit ]
      # API-06: the steps of a call; "dispatch" is a name Rails keeps for itself.
      post "calls/:id/dispatch" => "call_steps#send_car", as: :call_dispatch
      post "calls/:id/arrival" => "call_steps#arrive", as: :call_arrival
      post "calls/:id/close" => "call_steps#close", as: :call_close
      post "calls/:id/cancel" => "call_steps#cancel", as: :call_cancel
      resource :statistics, only: :show
      resources :addresses, only: :index
    end
  end
end
