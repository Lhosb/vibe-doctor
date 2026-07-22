class CreateQueryUnderstandingCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :query_understanding_caches do |t|
      t.string :query_digest, null: false
      t.text :query_text, null: false
      t.float :valence, null: false
      t.float :arousal, null: false
      t.float :danceability, null: false
      t.float :mood_acoustic, null: false
      t.float :mood_relaxed, null: false
      t.float :mood_happy, null: false
      t.string :genre
      t.jsonb :keywords, null: false, default: []
      t.vector :embedding, limit: 1536, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :query_understanding_caches, :query_digest, unique: true
  end
end
