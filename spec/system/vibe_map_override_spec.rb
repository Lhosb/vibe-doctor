require "rails_helper"

RSpec.describe "Vibe map override", type: :system, js: true do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, genres: [ "Jazz" ]) }

  before do
    sign_in_as(user)
    visit album_path(album)
  end

  it "creates a vibe_map-sourced override when the listener clicks a point on the map" do
    find(".vibe-map").click

    expect(page).to have_css(".vibe-map--saved")
    expect(VibeOverride.find_by(user: user, album: album).source).to eq("vibe_map")
  end
end
