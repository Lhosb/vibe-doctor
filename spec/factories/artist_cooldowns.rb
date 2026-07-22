FactoryBot.define do
  factory :artist_cooldown do
    user
    artist_name { "Nas" }
    last_recommended_at { Time.current }
  end
end
