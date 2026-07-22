require "rails_helper"

RSpec.describe Album do
  describe "#recommendation_stats" do
    let(:album) { create(:album, :grounded) }

    it "aggregates recommendation outcomes for the album" do
      create(:recommendation_event, album: album, outcome: "good", final_score: 0.8)
      create(:recommendation_event, album: album, outcome: "bad", final_score: 0.4)
      create(:recommendation_event, album: album, outcome: "pending", final_score: 0.6)

      stats = album.recommendation_stats

      expect(stats).to include(
        total_recommended: 3,
        good_count: 1,
        bad_count: 1,
        skip_count: 0,
        pending_count: 1
      )
      expect(stats[:average_final_score]).to eq(0.6)
    end

    it "returns zeroed stats for an album with no recommendation history" do
      expect(album.recommendation_stats).to include(
        total_recommended: 0,
        good_count: 0,
        bad_count: 0,
        skip_count: 0,
        pending_count: 0,
        average_final_score: nil
      )
    end
  end
end
