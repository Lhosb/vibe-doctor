class CreateMoodVectors < ActiveRecord::Migration[8.1]
  def change
    create_table :mood_vectors do |t|
      t.references :album, null: false, foreign_key: true, index: { unique: true }
      t.float :valence, null: false, default: 0.5
      t.float :arousal, null: false, default: 0.5
      t.float :danceability, null: false, default: 0.5
      t.float :mood_acoustic, null: false, default: 0.5
      t.float :mood_relaxed, null: false, default: 0.5
      t.float :mood_happy, null: false, default: 0.5
      t.string :mood_source, null: false, default: "llm_only"
      t.float :match_confidence, null: false, default: 0.0
      t.jsonb :spread, null: false, default: {}

      t.timestamps
    end
    add_check_constraint :mood_vectors,
      "mood_source IN ('essentia_itunes', 'essentia_youtube', 'llm_only')",
      name: "mood_vectors_mood_source_check"
  end
end
