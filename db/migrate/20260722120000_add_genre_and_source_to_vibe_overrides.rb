class AddGenreAndSourceToVibeOverrides < ActiveRecord::Migration[8.1]
  def change
    add_column :vibe_overrides, :genre, :string
    add_column :vibe_overrides, :source, :string
  end
end
