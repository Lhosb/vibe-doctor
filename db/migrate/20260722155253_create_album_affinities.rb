class CreateAlbumAffinities < ActiveRecord::Migration[8.1]
  def change
    create_table :album_affinities do |t|
      t.references :user, null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.float :score, null: false, default: 0.0
      t.datetime :last_interacted_at

      t.timestamps
    end

    add_index :album_affinities, [:user_id, :album_id], unique: true
  end
end
