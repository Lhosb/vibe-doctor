class SyncDiscogsCollectionJob < ApplicationJob
  queue_as :default

  def perform(user)
    client = DiscogsClient.new(token: user.discogs_token)
    releases = client.collection_releases(username: user.discogs_username)

    releases.each do |release|
      info = release["basic_information"]
      next if info.blank? || info["id"].blank?

      album = find_or_create_album(info)

      CollectionItem.find_or_create_by!(user: user, release_id: info["id"]) do |item|
        item.album = album
      end
    end
  end

  private

  def find_or_create_album(info)
    master_id = info["master_id"].presence&.nonzero?
    key = master_id || info["id"]

    album = Album.find_or_create_by!(master_id: key) do |new_album|
      new_album.synthetic_master_id = master_id.nil?
      new_album.title = info["title"].to_s
      new_album.artists = Array(info["artists"]).filter_map { |artist| artist["name"] }
      new_album.year = info["year"]
      new_album.genres = Array(info["genres"])
      new_album.styles = Array(info["styles"])
    end

    EnrichAlbumJob.perform_later(album) if album.previously_new_record?
    album
  end
end
