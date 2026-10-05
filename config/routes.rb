Rails.application.routes.draw do
  # Health check for the deployment proxy: 200 when the application boots.
  get "up" => "rails/health#show", as: :rails_health_check
  # CRW-01: the app manifest, so the crew screen installs on a phone.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # CRW-04: the service worker that shows the crew's notices.
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  # CRW-01: the Home Screen icon by the names an iPhone asks for itself.
  get "apple-touch-icon" => "touch_icons#show", constraints: { format: "png" }
  get "apple-touch-icon-precomposed" => "touch_icons#show", constraints: { format: "png" }
  # API-11: what Traccar Client sends, open to it (BR-13).
  match "traccar" => "traccar#create", via: %i[ get post ], as: :traccar

  resource :session, only: %i[ new create destroy ]
  get "captcha" => "captcha#challenge", as: :captcha_challenge
  get "auth/google_oauth2/callback" => "google_sessions#create"
  get "auth/failure" => "google_sessions#failure"

  root "board#index"
  resource :call_cleanup, path: "calls/cleanup", only: %i[ new create ]
  resources :calls, only: %i[ index show new create edit update destroy ] do
    resource :dispatch, only: %i[ new create ]
    resource :acceptance, only: :create
    resource :arrival, only: :create
    resource :closing, only: %i[ new create ]
    resource :cancellation, only: %i[ new create ]
    # UPD-14 … UPD-16: the further cars of a call and their own steps.
    resources :backups, only: %i[ new create ] do
      member do
        post :accept
        post :arrive
        post :release
      end
    end
    # UPD-13: a crew's SOS is seen by a dispatcher.
    resource :acknowledgement, only: :create
    resources :photos, only: %i[ create show ], controller: "call_photos"
  end
  resources :guarded_sites, path: "sites"
  resources :addresses, only: :index
  resources :patrol_cars, path: "cars"
  resource :map, only: :show
  resource :crew, only: :show do
    # TRK-04: the crew's phone as the position source of its car.
    resource :position, only: :create, controller: "crew_positions"
    # ADD-12: the crew asks for help; the question first, then the signal.
    resource :sos, only: %i[ new create ], controller: "crew_sos"
  end
  resource :push_subscription, only: %i[ create destroy ]
  # TRK-01, TRK-02: the administrator's page of car tracking.
  resource :tracking, only: :show
  patch "tracking/cars/:patrol_car_id/source" => "trackings#choose_source", as: :tracking_car_source
  post "tracking/cars/:patrol_car_id/key" => "trackings#issue_key", as: :tracking_car_key
  # TRK-05, DEL-09: the administrator's settings — for how many months car
  # positions and calls are kept.
  resource :settings, only: :show
  patch "settings/positions" => "settings#keep_positions", as: :settings_positions
  patch "settings/calls" => "settings#keep_calls", as: :settings_calls
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
  # USR-05, USR-06: a user's own page and the change of their password.
  resource :profile, only: :show do
    # USR-07: the user's own picture.
    resource :picture, only: %i[ edit update destroy ], controller: "profile_pictures" do
      post :gravatar
    end
  end
  get "users/:id/picture" => "user_pictures#show", as: :user_picture
  resource :password, path: "profile/password", only: %i[ edit update ]

  # 4.2: the API, with the personal API key of the user (BR-13).
  namespace :api do
    namespace :v1, defaults: { format: :json } do
      resources :sites, except: %i[ new edit ]
      resources :patrol_cars, except: %i[ new edit ]
      resources :calls, except: %i[ new edit ]
      # API-06: the steps of a call; "dispatch" is a name Rails keeps for itself.
      post "calls/:id/dispatch" => "call_steps#send_car", as: :call_dispatch
      post "calls/:id/accept" => "call_steps#accept", as: :call_accept
      post "calls/:id/arrival" => "call_steps#arrive", as: :call_arrival
      post "calls/:id/close" => "call_steps#close", as: :call_close
      post "calls/:id/cancel" => "call_steps#cancel", as: :call_cancel
      resource :statistics, only: :show
      resources :addresses, only: :index
    end
  end
end
