require "rails_helper"

RSpec.describe RecommendationEvent do
  it "requires query_text, candidates_considered, and final_score" do
    event = described_class.new(user: create(:user), album: create(:album, :grounded))
    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to contain_exactly(:query_text, :candidates_considered, :final_score)
  end

  it "persists score snapshots as JSON" do
    event = create(:recommendation_event, blended_scores: { "1" => 0.2 }, rerank_scores: { "1" => 0.9 })
    expect(event.reload.blended_scores).to eq("1" => 0.2)
    expect(event.reload.rerank_scores).to eq("1" => 0.9)
  end
end
