require "rails_helper"

RSpec.describe VibeCard, type: :model do
  let(:album) { Album.create!(master_id: 1, title: "Nevermind") }

  it "is valid with defaults, scoped to an album" do
    expect(VibeCard.new(album: album)).to be_valid
  end

  it "requires an album" do
    expect(VibeCard.new).not_to be_valid
  end

  it "stores array fields" do
    card = VibeCard.create!(album: album, time_of_day: %w[evening], activities: [ "winding down" ])
    expect(card.reload.time_of_day).to eq(%w[evening])
    expect(card.activities).to eq([ "winding down" ])
  end
end
