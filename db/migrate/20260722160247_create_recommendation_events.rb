class CreateRecommendationEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :recommendation_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.text :query_text, null: false
      t.integer :candidates_considered, null: false
      t.jsonb :blended_scores, null: false, default: {}
      t.jsonb :rerank_scores, null: false, default: {}
      t.float :final_score, null: false
      t.string :outcome, null: false, default: "pending"
      t.text :explanation

      t.timestamps
    end

    add_index :recommendation_events, :outcome
  end

  def down
    remove_index :recommendation_events, :outcome if index_exists?(:recommendation_events, :outcome)
    drop_table :recommendation_events, if_exists: true
  end
end
