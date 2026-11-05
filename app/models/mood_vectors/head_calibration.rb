module MoodVectors
  class HeadCalibration
    EMOMUSIC_HEADS = %i[valence arousal].freeze
    RAW_MIN = 1.0
    RAW_RANGE = 8.0
    BAND_MIN = 3.0
    BAND_MAX = 7.0
    BAND_RANGE = BAND_MAX - BAND_MIN

    class << self
      def album_coordinate(mood_vector, head)
        value = mood_vector.public_send(head)
        return value unless EMOMUSIC_HEADS.include?(head)

        (stored_to_raw(value) - BAND_MIN) / BAND_RANGE
      end

      private

      def stored_to_raw(value)
        (value * RAW_RANGE) + RAW_MIN
      end
    end
  end
end
