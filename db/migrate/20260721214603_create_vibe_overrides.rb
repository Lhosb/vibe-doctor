class CreateVibeOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :vibe_overrides do |t|
      t.references :user, null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.float :valence
      t.float :arousal
      t.float :danceability
      t.float :mood_acoustic
      t.float :mood_relaxed
      t.float :mood_happy

      t.timestamps
    end
    add_index :vibe_overrides, %i[user_id album_id], unique: true
  end
end
