class MoodVector < ApplicationRecord
  MOOD_SOURCES = %w[essentia_itunes essentia_youtube llm_only].freeze
  MOOD_HEADS = %i[valence arousal danceability mood_acoustic mood_relaxed mood_happy].freeze
  MAX_DISTANCE = Math.sqrt(MOOD_HEADS.size)

  belongs_to :album

  validates :mood_source, inclusion: { in: MOOD_SOURCES }
  validates(*MOOD_HEADS, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 })

  def distance_to(other)
    Math.sqrt(MOOD_HEADS.sum { |head| (send(head) - other.send(head))**2 })
  end

  def vibe_phrase(genre: nil)
    MoodVectors::VibePhraseBuilder.new(self, genre: genre).call
  end
end
