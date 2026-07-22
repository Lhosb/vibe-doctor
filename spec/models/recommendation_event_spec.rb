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

  describe "#apply_outcome!" do
    let(:user) { create(:user) }
    let(:album) { create(:album, :grounded) }
    let(:event) { create(:recommendation_event, user: user, album: album) }

    it "transitions from pending to good and rewards affinity" do
      event.apply_outcome!("good")

      expect(event.reload.outcome).to eq("good")
      expect(AlbumAffinity.find_by(user: user, album: album).score).to eq(0.15)
    end

    it "penalizes affinity on a bad outcome" do
      create(:album_affinity, user: user, album: album, score: 0.1)

      event.apply_outcome!("bad")

      expect(AlbumAffinity.find_by(user: user, album: album).score).to be_within(0.0001).of(-0.1)
    end

    it "applies a smaller penalty on skip" do
      event.apply_outcome!("skip")

      expect(AlbumAffinity.find_by(user: user, album: album).score).to eq(-0.05)
    end

    it "clamps the affinity score to [-1.0, 1.0]" do
      create(:album_affinity, user: user, album: album, score: 0.95)

      event.apply_outcome!("good")

      expect(AlbumAffinity.find_by(user: user, album: album).score).to eq(1.0)
    end

    it "raises on an unknown outcome" do
      expect { event.apply_outcome!("meh") }.to raise_error(RecommendationEvent::InvalidOutcomeTransitionError)
    end

    it "raises when the event already has a terminal outcome" do
      event.apply_outcome!("good")

      expect { event.apply_outcome!("bad") }.to raise_error(RecommendationEvent::InvalidOutcomeTransitionError)
    end
  end

  describe ".pending_for" do
    it "returns only the given user's pending events, oldest first" do
      user = create(:user)
      other_user = create(:user)
      older = create(:recommendation_event, user: user, created_at: 2.days.ago)
      newer = create(:recommendation_event, user: user, created_at: 1.day.ago)
      create(:recommendation_event, user: user, outcome: "good")
      create(:recommendation_event, user: other_user)

      expect(described_class.pending_for(user)).to eq([older, newer])
    end
  end
end
