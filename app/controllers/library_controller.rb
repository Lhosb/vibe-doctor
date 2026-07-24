class LibraryController < ApplicationController
  def index
    @collection_items = Current.user.collection_items
      .includes(:album)
      .joins(:album)
      .order("albums.artists ASC, albums.title ASC")
  end
end
