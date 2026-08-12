module MoodVectors
  class EssentiaMapper
    DESCRIPTORS = %w[
      valence_emomusic
      arousal_emomusic
      danceability
      mood_acoustic
      mood_relaxed
      mood_happy
    ].freeze

    def call(descriptors)
      {
        valence: rescale_emomusic(descriptors.fetch("valence_emomusic")),
        arousal: rescale_emomusic(descriptors.fetch("arousal_emomusic")),
        danceability: clamp(descriptors.fetch("danceability")),
        mood_acoustic: clamp(descriptors.fetch("mood_acoustic")),
        mood_relaxed: clamp(descriptors.fetch("mood_relaxed")),
        mood_happy: clamp(descriptors.fetch("mood_happy"))
      }
    end

    private

    def rescale_emomusic(value)
      clamp((value - 1.0) / 8.0)
    end

    def clamp(value)
      value.clamp(0.0, 1.0)
    end
  end
end
