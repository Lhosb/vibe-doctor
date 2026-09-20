class AddMoodHeadSharesToRecommendationEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :recommendation_events, :mood_head_shares, :jsonb, default: {}, null: false,
      comment: "Normalized mood-head shares over all pre-filter scored candidates; scored_count differs from candidates_considered."
  end
end
