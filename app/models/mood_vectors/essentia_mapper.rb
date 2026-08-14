module MoodVectors
  class EssentiaMapper
    # Source citation, not a machine check: sonance registry.rb default_descriptors at v0.3.0,
    # peeled SHA 66393972a8b57ee116afec0fbeb879a0c410dbca. Slice 5b adds the construction assertion
    # that this set is a subset of Sonance::Registry.default.ids after the gem is pinned.
    DESCRIPTORS = %i[
      valence_emomusic
      arousal_emomusic
      danceability_musicnn
      mood_acoustic_musicnn
      mood_relaxed_musicnn
      mood_happy_musicnn
    ].freeze
    EMOMUSIC_RANGE = (1.0..9.0).freeze

    # Inputs are expected to have passed sonance's loud registry range validation upstream;
    # clamping here is normalization, not malformed-output validation.
    def call(descriptors)
      validate_descriptors!(descriptors)

      {
        valence: rescale_emomusic(descriptors.fetch(:valence_emomusic)),
        arousal: rescale_emomusic(descriptors.fetch(:arousal_emomusic)),
        danceability: clamp(descriptors.fetch(:danceability_musicnn)),
        mood_acoustic: clamp(descriptors.fetch(:mood_acoustic_musicnn)),
        mood_relaxed: clamp(descriptors.fetch(:mood_relaxed_musicnn)),
        mood_happy: clamp(descriptors.fetch(:mood_happy_musicnn))
      }
    end

    private

    def validate_descriptors!(descriptors)
      missing = DESCRIPTORS - descriptors.keys
      unexpected = descriptors.keys - DESCRIPTORS
      problems = []
      problems << "missing descriptors: #{missing.join(", ")}" if missing.any?
      problems << "unexpected descriptors: #{unexpected.join(", ")}" if unexpected.any?

      raise ArgumentError, problems.join("; ") if problems.any?
    end

    def rescale_emomusic(value)
      clamp((value - 1.0) / 8.0)
    end

    def clamp(value)
      value.clamp(0.0, 1.0)
    end
  end
end
