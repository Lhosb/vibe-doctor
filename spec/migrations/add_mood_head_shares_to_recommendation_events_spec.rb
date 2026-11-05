require "rails_helper"
require Rails.root.join("db/migrate/20260920160748_add_mood_head_shares_to_recommendation_events")

RSpec.describe AddMoodHeadSharesToRecommendationEvents do
  it "sets a transaction-local lock timeout before adding the column" do
    migration = described_class.new
    operations = []

    allow(migration).to receive(:execute) { |sql| operations << [ :execute, sql ] }
    allow(migration).to receive(:add_column) do |table, column, type, **options|
      operations << [ :add_column, table, column, type, options ]
    end

    migration.migrate(:up)

    expect(operations).to eq(
      [
        [ :execute, "SET LOCAL lock_timeout = '5s'" ],
        [
          :add_column,
          :recommendation_events,
          :mood_head_shares,
          :jsonb,
          {
            default: {},
            null: false,
            comment: "Normalized mood-head shares over all pre-filter scored candidates; scored_count differs from candidates_considered."
          }
        ]
      ]
    )
  end
end
