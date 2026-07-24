class AlbumsController < ApplicationController
  def show
    @album = Album.find(params[:id])
    override = VibeOverride.find_by(user: Current.user, album: @album)
    @vibe_mood = override&.mood_snapshot || @album.mood_vector
  end
end
