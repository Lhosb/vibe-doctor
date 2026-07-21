class VibeOverride < ApplicationRecord
  MOOD_HEADS = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].freeze

  belongs_to :user
  belongs_to :album

  validates :album_id, uniqueness: { scope: :user_id }
end
