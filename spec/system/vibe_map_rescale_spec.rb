require "rails_helper"

RSpec.describe "Vibe Map drag inversion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:low_album) { create(:album, :grounded, title: "Low Album") }
  let(:high_album) { create(:album, :grounded, title: "High Album") }

  # Deliberately asymmetric ranges (not centered on 0.5): dragging to the
  # canvas's exact center inverts to a value other than 0.5 given these
  # ranges, so this fixture actually distinguishes "inverted via the current
  # zoomed/auto-fit axis extent" from "some other, wrong, transform" -- a
  # symmetric 0.2/0.8 range would invert center-drag back to 0.5 either way
  # and prove nothing.
  before do
    create(:mood_vector, album: low_album, valence: 0.2, arousal: 0.3)
    create(:mood_vector, album: high_album, valence: 0.6, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_album, release_id: 1)
    CollectionItem.create!(user: user, album: high_album, release_id: 2)
    sign_in_as(user)
  end

  it "inverts a dragged position back into true valence/arousal via the chart's current axis extent" do
    visit vibe_map_path

    point = find_vibe_map_point(low_album, valence: 0.2, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{low_album.id}']")

    override = VibeOverride.find_by(user: user, album: low_album)
    expect(override.valence).to be_within(0.1).of(0.4)
    expect(override.arousal).to be_within(0.1).of(0.4)
  end
end
