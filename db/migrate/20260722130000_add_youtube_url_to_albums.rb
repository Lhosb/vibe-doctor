class AddYoutubeUrlToAlbums < ActiveRecord::Migration[8.1]
  def change
    add_column :albums, :youtube_url, :string
  end
end
