module Albums
  class VibeMapBuilder
    Dot = Struct.new(
      :album, :valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy, :phrase,
      keyword_init: true
    )

    def initialize(collection_items, user: nil)
      @collection_items = collection_items
      @user = user
    end

    def dots
      @dots ||= albums.map do |album|
        mood = moods[album]
        genre = album.genres.first

        Dot.new(
          album: album,
          valence: mood.valence,
          arousal: mood.arousal,
          danceability: mood.danceability,
          mood_acoustic: mood.mood_acoustic,
          mood_relaxed: mood.mood_relaxed,
          mood_happy: mood.mood_happy,
          phrase: MoodVectors::VibePhraseBuilder.new(mood, genre: genre).call
        )
      end
    end

    def dots_json
      dots.map do |dot|
        {
          id: dot.album.id,
          title: dot.album.title,
          href: Rails.application.routes.url_helpers.album_path(dot.album),
          valence: dot.valence,
          arousal: dot.arousal,
          genre: dot.album.genres.first,
          phrase: dot.phrase,
          danceability: dot.danceability,
          mood_acoustic: dot.mood_acoustic,
          mood_relaxed: dot.mood_relaxed,
          mood_happy: dot.mood_happy
        }
      end.to_json
    end

    private

    attr_reader :collection_items, :user

    def albums
      @albums ||= collection_items
        .joins(:album)
        .merge(Album.grounded)
        .includes(album: :mood_vector)
        .map(&:album)
    end

    def moods
      @moods ||= albums.index_with { |album| overrides[album.id] || album.mood_vector }
    end

    def overrides
      @overrides ||= begin
        scope = VibeOverride.where(album_id: albums.map(&:id))
        scope = scope.where(user: user) if user
        scope.index_by(&:album_id)
      end
    end
  end
end
