require "rails_helper"

RSpec.describe VibeOverride, type: :model do
  let(:user) { create(:user) }
  let(:album) { Album.create!(master_id: 1, title: "Nevermind") }

  it "is valid with only a sparse subset of fields set" do
    override = VibeOverride.new(user: user, album: album, valence: 0.8)
    expect(override).to be_valid
    expect(override.arousal).to be_nil
  end

  it "allows only one override row per user per album" do
    VibeOverride.create!(user: user, album: album, valence: 0.8)
    duplicate = VibeOverride.new(user: user, album: album, arousal: 0.2)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:album_id]).to be_present
  end
end
