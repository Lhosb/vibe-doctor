FactoryBot.define do
  factory :mood_vector do
    album
    valence { 0.5 }
    arousal { 0.5 }
    danceability { 0.5 }
    mood_acoustic { 0.5 }
    mood_relaxed { 0.5 }
    mood_happy { 0.5 }
    mood_source { "llm_only" }
    match_confidence { 0.0 }
    spread { {} }
  end
end
