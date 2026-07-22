class AddOutcomeToRecommendationEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :recommendation_events, :outcome, :string, null: false, default: "pending"
    add_index :recommendation_events, :outcome
  end
end
