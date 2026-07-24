class DiscogsConnectionsController < ApplicationController
  def edit
  end

  def update
    Current.user.update!(discogs_connection_params)
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end

  def resync
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end

  private

  def discogs_connection_params
    params.permit(:discogs_username, :discogs_token)
  end
end
