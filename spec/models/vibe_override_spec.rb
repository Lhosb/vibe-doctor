require "rails_helper"

RSpec.describe VibeOverride do
  describe ".upsert_for!" do
    let(:user) { create(:user) }
    let(:album) { create(:album, :grounded) }
    let(:mood_snapshot) do
      VibeOverride::MoodSnapshot.new(
        valence: 0.2, arousal: 0.4, danceability: 0.3,
        mood_acoustic: 0.6, mood_relaxed: 0.7, mood_happy: 0.5
      )
    end

    it "creates an override on first call" do
      override = described_class.upsert_for!(
        user: user, album: album, mood_snapshot: mood_snapshot, genre: "Ambient", source: "album_detail"
      )

      expect(override).to be_persisted
      expect(override.mood_snapshot).to have_attributes(valence: 0.2, mood_happy: 0.5)
      expect(override.genre).to eq("Ambient")
      expect(override.source).to eq("album_detail")
    end

    it "updates the existing override instead of creating a second row" do
      described_class.upsert_for!(user: user, album: album, mood_snapshot: mood_snapshot, source: "vibe_map")
      updated_snapshot = VibeOverride::MoodSnapshot.new(
        valence: 0.5, arousal: 0.5, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5
      )

      described_class.upsert_for!(user: user, album: album, mood_snapshot: updated_snapshot, source: "album_detail")

      expect(described_class.where(user: user, album: album).count).to eq(1)
      expect(described_class.find_by(user: user, album: album)).to have_attributes(valence: 0.5, source: "album_detail")
    end

    it "rejects an unknown source" do
      expect {
        described_class.upsert_for!(user: user, album: album, mood_snapshot: mood_snapshot, source: "bogus")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
