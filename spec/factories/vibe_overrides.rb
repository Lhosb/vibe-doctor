FactoryBot.define do
  factory :vibe_override do
    user
    album
    valence { 0.2 }
    arousal { 0.4 }
    danceability { 0.3 }
    mood_acoustic { 0.6 }
    mood_relaxed { 0.7 }
    mood_happy { 0.5 }
    genre { "Ambient" }
    source { "album_detail" }
  end
end
