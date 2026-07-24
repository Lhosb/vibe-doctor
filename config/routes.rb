Rails.application.routes.draw do
  draw :madmin
  root "library#index"
  get "library" => "library#index", as: :library
  get "vibe_map" => "vibe_map#index", as: :vibe_map
  get "vibe_map/global" => "vibe_map#global", as: :global_vibe_map
  resource :discogs_connection, only: %i[edit update] do
    post :resync, on: :collection
  end
  resource :session
  resources :passwords, param: :token
  resources :registrations, param: :token, only: [ :edit, :update ]
  get "/feedback", to: "feedback#index"
  post "/feedback", to: "feedback#create"
  get "/recommend", to: "recommend#index", as: :recommend
  post "/recommend", to: "recommendations#create"
  post "/recommend/feedback", to: "recommendations#feedback"
  resources :albums, only: [ :show ] do
    resource :vibe_override, only: [ :create ], controller: "vibe_overrides"
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
