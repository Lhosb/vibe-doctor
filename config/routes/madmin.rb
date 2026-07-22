# Below are the routes for madmin
namespace :madmin, path: "admin" do
  resources :embeddings
  resources :mood_vectors
  resources :query_understanding_caches
  resources :recommendation_events
  resources :sessions
  resources :users
  resources :vibe_cards
  resources :vibe_overrides
  resources :artist_cooldowns
  resources :collection_items
  resources :albums do
    post :repair_youtube_link, on: :member
    get :recommendation_stats, on: :member
  end
  resources :album_affinities
  root to: "dashboard#show"
end
