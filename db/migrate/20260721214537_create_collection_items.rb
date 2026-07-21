class CreateCollectionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.bigint :release_id, null: false

      t.timestamps
    end
    add_index :collection_items, %i[user_id release_id], unique: true
  end
end
