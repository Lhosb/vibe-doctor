class CreateAlbums < ActiveRecord::Migration[8.1]
  def change
    create_table :albums do |t|
      t.bigint :master_id, null: false
      t.boolean :synthetic_master_id, null: false, default: false
      t.string :title, null: false
      t.string :artists, array: true, null: false, default: []
      t.integer :year
      t.string :genres, array: true, null: false, default: []
      t.string :styles, array: true, null: false, default: []
      t.string :enrichment_status, null: false, default: "pending"

      t.timestamps
    end
    add_index :albums, :master_id, unique: true
  end
end
