FactoryBot.define do
  factory :album_affinity do
    user
    album
    score { 0.5 }
    last_interacted_at { Time.current }
  end
end
