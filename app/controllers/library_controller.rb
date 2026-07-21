class LibraryController < ApplicationController
  def index
    @collection_items = Current.user.collection_items.includes(:album).order(:id)
  end
end
