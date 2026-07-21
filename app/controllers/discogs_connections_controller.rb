class DiscogsConnectionsController < ApplicationController
  def new
  end

  def create
    Current.user.update!(params.permit(:discogs_username, :discogs_token))
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end
end
