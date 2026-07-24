class CreateArtistCooldowns < ActiveRecord::Migration[8.1]
  def change
    create_table :artist_cooldowns do |t|
      t.references :user, null: false, foreign_key: true
      t.string :artist_name, null: false
      t.datetime :last_recommended_at, null: false

      t.timestamps
    end

    add_index :artist_cooldowns, [ :user_id, :artist_name ], unique: true
  end
end
