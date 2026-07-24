module MoodVectors
  class VibePhraseBuilder
    ADJECTIVES = {
      valence: { low: "somber", high: "sunny" },
      arousal: { low: "hushed", high: "driving" },
      danceability: { low: "static", high: "danceable" },
      mood_acoustic: { low: "electric", high: "acoustic" },
      mood_relaxed: { low: "tense", high: "mellow" },
      mood_happy: { low: "brooding", high: "joyful" }
    }.freeze

    NEUTRAL = 0.5
    DISTINCTIVE_THRESHOLD = 0.1

    def initialize(mood, genre: nil)
      @mood = mood
      @genre = genre
    end

    def call
      adjectives = distinctive_heads.first(2).map { |head| adjective_for(head) }
      [ adjectives.join(" "), @genre ].select(&:present?).join(" — ")
    end

    private

    def distinctive_heads
      MoodVector::MOOD_HEADS.each_with_index
        .select { |head, _index| distance(head) > DISTINCTIVE_THRESHOLD }
        .sort_by { |head, index| [ -distance(head), index ] }
        .map(&:first)
    end

    def distance(head)
      (@mood.send(head) - NEUTRAL).abs
    end

    def adjective_for(head)
      band = @mood.send(head) > 0.6 ? :high : :low
      ADJECTIVES.fetch(head).fetch(band)
    end
  end
end
