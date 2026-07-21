class AddDiscogsFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, null: false, default: false
    add_column :users, :discogs_username, :string
    add_column :users, :discogs_token, :string
  end
end
