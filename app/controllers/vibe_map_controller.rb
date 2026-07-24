class VibeMapController < ApplicationController
  Dot = Struct.new(
    :album, :valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy, :phrase,
    :x_percent, :y_percent,
    keyword_init: true
  )

  def index
    collection_items = Current.user.collection_items
      .joins(:album)
      .merge(Album.grounded)
      .includes(album: :mood_vector)

    albums = collection_items.map(&:album)
    overrides = VibeOverride.where(user: Current.user, album_id: albums.map(&:id)).index_by(&:album_id)
    moods = albums.index_with { |album| overrides[album.id] || album.mood_vector }

    @valence_min, @valence_max = minmax(moods.values.map(&:valence))
    @arousal_min, @arousal_max = minmax(moods.values.map(&:arousal))

    @dots = albums.map do |album|
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
        phrase: MoodVectors::VibePhraseBuilder.new(mood, genre: genre).call,
        x_percent: rescale(mood.valence, @valence_min, @valence_max),
        y_percent: 100 - rescale(mood.arousal, @arousal_min, @arousal_max)
      )
    end
  end

  private

  def minmax(values)
    return [ 0.0, 1.0 ] if values.empty?

    [ values.min, values.max ]
  end

  def rescale(value, min, max)
    return (value * 100).round(2) if min == max

    (((value - min) / (max - min).to_f) * 100).round(2)
  end
end
