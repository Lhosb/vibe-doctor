class CreateVibeCards < ActiveRecord::Migration[8.1]
  def change
    create_table :vibe_cards do |t|
      t.references :album, null: false, foreign_key: true, index: { unique: true }
      t.string :time_of_day, array: true, null: false, default: []
      t.string :activities, array: true, null: false, default: []
      t.string :energy_arc, null: false, default: ""
      t.string :texture, null: false, default: ""
      t.string :seasons, array: true, null: false, default: []
      t.text :prose, null: false, default: ""

      t.timestamps
    end
  end
end
