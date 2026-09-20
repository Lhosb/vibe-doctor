module MoodVectors
  class EssentiaMapper
    # Source: sonance registry.rb default_descriptors at v0.4.0, peeled SHA
    # 1115824c8fec533037c35aaf4ec091bb42ac63df. The registry contract is enforced at boot in
    # config/initializers/sonance_registry.rb and in spec/models/mood_vectors/essentia_registry_contract_spec.rb.
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
