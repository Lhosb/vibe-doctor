class VibeMapController < ApplicationController
  Dot = Struct.new(
    :album, :valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy, :phrase,
    keyword_init: true
  )

  def index
    collection_items = Current.user.collection_items
      .joins(:album)
      .merge(Album.grounded)
      .includes(album: :mood_vector)

    albums = collection_items.map(&:album)
    overrides = VibeOverride.where(user: Current.user, album_id: albums.map(&:id)).index_by(&:album_id)

    @dots = albums.map do |album|
      mood = overrides[album.id] || album.mood_vector
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
end
