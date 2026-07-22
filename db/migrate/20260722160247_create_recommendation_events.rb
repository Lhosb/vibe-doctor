class CreateRecommendationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendation_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.text :query_text, null: false
      t.integer :candidates_considered, null: false
      t.jsonb :blended_scores, null: false, default: {}
      t.jsonb :rerank_scores, null: false, default: {}
      t.float :final_score, null: false
      t.text :explanation

      t.timestamps
    end
  end
end
