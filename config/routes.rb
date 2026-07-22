Rails.application.routes.draw do
  root "library#index"
  get "library" => "library#index", as: :library
  resource :discogs_connection, only: %i[new create]
  resource :session
  resources :passwords, param: :token
  get "/feedback", to: "feedback#index"
  post "/feedback", to: "feedback#create"
  post "/recommend", to: "recommendations#create"
  post "/recommend/feedback", to: "recommendations#feedback"
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
