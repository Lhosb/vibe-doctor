module MoodVectors
  class MoodDistance
    class << self
      def term(album_mood:, query_mood:)
        squared_distance = MoodVector::MOOD_HEADS.sum do |head|
          album_coordinate = HeadCalibration.album_coordinate(album_mood, head)
          delta = album_coordinate - query_mood.public_send(head)

          HeadWeights.for(head) * delta**2
        end

        Math.sqrt(squared_distance) / HeadWeights.max_distance
      end
    end
  end
end
