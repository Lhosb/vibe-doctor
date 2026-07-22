class AddOutcomeToRecommendationEvents < ActiveRecord::Migration[8.1]
  def change
    return unless table_exists?(:recommendation_events)

    add_column :recommendation_events, :outcome, :string, null: false, default: "pending" unless column_exists?(:recommendation_events, :outcome)
    add_index :recommendation_events, :outcome unless index_exists?(:recommendation_events, :outcome)
  end
end
