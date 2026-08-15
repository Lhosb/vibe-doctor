require "set"

module MoodVectors
  class HeadWeights
    WEIGHTS = {
      valence: 1.0,
      arousal: 1.0,
      danceability: 1.0,
      mood_acoustic: 1.0,
      mood_happy: 1.0,
      mood_relaxed: 1.0
    }.freeze

    class << self
      def for(head)
        WEIGHTS.fetch(head)
      end

      def max_distance
        Math.sqrt(WEIGHTS.values.sum)
      end

      def validate!(weights)
        expected_heads = MoodVector::MOOD_HEADS.to_set
        raise ArgumentError, "head-weights keys must match MoodVector::MOOD_HEADS" unless weights.keys.to_set == expected_heads

        weights.each do |head, value|
          unless value.is_a?(Numeric) && value.finite? && value.positive?
            raise ArgumentError, "head-weights value for #{head} must be finite and positive"
          end
        end

        true
      end
    end

    validate!(WEIGHTS)
  end
end
