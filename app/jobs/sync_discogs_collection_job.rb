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

    Album.find_or_create_by!(master_id: key) do |album|
      album.synthetic_master_id = master_id.nil?
      album.title = info["title"].to_s
      album.artists = Array(info["artists"]).filter_map { |artist| artist["name"] }
      album.year = info["year"]
      album.genres = Array(info["genres"])
      album.styles = Array(info["styles"])
    end
  end
end
