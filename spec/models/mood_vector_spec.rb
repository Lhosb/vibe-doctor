require "rails_helper"

RSpec.describe MoodVector, type: :model do
  let(:album) { Album.create!(master_id: 1, title: "Nevermind") }

  it "is valid with defaults, scoped to an album" do
    expect(MoodVector.new(album: album)).to be_valid
  end

  it "requires an album" do
    expect(MoodVector.new).not_to be_valid
  end

  it "restricts mood_source to the known set" do
    mood_vector = MoodVector.new(album: album, mood_source: "invented_source")
    expect(mood_vector).not_to be_valid
    expect(mood_vector.errors[:mood_source]).to be_present
  end

  it "restricts mood heads to the 0..1 range" do
    mood_vector = MoodVector.new(album: album, valence: 1.5)
    expect(mood_vector).not_to be_valid
    expect(mood_vector.errors[:valence]).to be_present
  end
end
