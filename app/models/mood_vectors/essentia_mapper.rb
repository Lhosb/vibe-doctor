module MoodVectors
  class EssentiaMapper
    # Source citation, not a machine check: mood_probe registry.rb default_descriptors at v0.2.0,
    # peeled SHA 848f6894a6022b5a32ae2b6b0c6898ac84986fa0. Slice 5b adds the construction assertion
    # that this set is a subset of MoodProbe::Registry.default.ids after the gem is pinned.
    DESCRIPTORS = %i[
      valence_emomusic
      arousal_emomusic
      danceability
      mood_acoustic
      mood_relaxed
      mood_happy
    ].freeze

    # Inputs are expected to have passed mood_probe's loud registry range validation upstream;
    # clamping here is normalization, not malformed-output validation.
    def call(descriptors)
      validate_descriptors!(descriptors)

      {
        valence: rescale_emomusic(descriptors.fetch(:valence_emomusic)),
        arousal: rescale_emomusic(descriptors.fetch(:arousal_emomusic)),
        danceability: clamp(descriptors.fetch(:danceability)),
        mood_acoustic: clamp(descriptors.fetch(:mood_acoustic)),
        mood_relaxed: clamp(descriptors.fetch(:mood_relaxed)),
        mood_happy: clamp(descriptors.fetch(:mood_happy))
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
