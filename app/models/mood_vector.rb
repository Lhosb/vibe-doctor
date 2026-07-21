class MoodVector < ApplicationRecord
  MOOD_SOURCES = %w[essentia_itunes essentia_youtube llm_only].freeze
  MOOD_HEADS = %i[valence arousal danceability mood_acoustic mood_relaxed mood_happy].freeze

  belongs_to :album

  validates :mood_source, inclusion: { in: MOOD_SOURCES }
  validates(*MOOD_HEADS, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 })
end
