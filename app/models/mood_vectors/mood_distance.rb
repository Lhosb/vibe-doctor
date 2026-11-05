module MoodVectors
  class MoodDistance
    Breakdown = Data.define(:per_head, :term)

    class << self
      def term(album_mood:, query_mood:)
        breakdown(album_mood:, query_mood:).term
      end

      def breakdown(album_mood:, query_mood:)
        per_head = MoodVector::MOOD_HEADS.to_h do |head|
          album_coordinate = HeadCalibration.album_coordinate(album_mood, head)
          delta = album_coordinate - query_mood.public_send(head)

          [ head, HeadWeights.for(head) * delta**2 ]
        end

        term = Math.sqrt(per_head.values.sum) / HeadWeights.max_distance

        Breakdown.new(per_head: per_head.freeze, term:)
      end
    end
  end
end
