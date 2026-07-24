require "rails_helper"

RSpec.describe ArtistCooldown do
  let(:user) { create(:user) }

  around do |example|
    described_class.clock = -> { Time.zone.parse("2026-07-21 12:00:00") }
    example.run
    described_class.clock = -> { Time.current }
  end

  describe ".penalty_for" do
    it "returns 0.0 when the artist has never been recommended" do
      expect(described_class.penalty_for(user: user, artist_name: "Nas")).to eq(0.0)
    end

    it "returns a positive penalty within the cooldown window" do
      create(:artist_cooldown, user: user, artist_name: "Nas", last_recommended_at: described_class.clock.call - 2.days)

      expect(described_class.penalty_for(user: user, artist_name: "Nas")).to be_between(0.0, 0.5).exclusive
    end

    it "returns 0.0 once the cooldown window has passed" do
      create(:artist_cooldown, user: user, artist_name: "Nas", last_recommended_at: described_class.clock.call - 30.days)

      expect(described_class.penalty_for(user: user, artist_name: "Nas")).to eq(0.0)
    end
  end

  describe ".record!" do
    it "upserts the last_recommended_at timestamp" do
      described_class.record!(user: user, artist_name: "Nas")
      expect(described_class.penalty_for(user: user, artist_name: "Nas")).to be > 0.0

      described_class.record!(user: user, artist_name: "Nas")
      expect(described_class.where(user: user, artist_name: "Nas").count).to eq(1)
    end
  end
end
