require "rails_helper"

RSpec.describe "Vibe Map rescaling", type: :system, js: true do
  let(:user) { create(:user) }
  let(:low_album) { create(:album, :grounded, title: "Low Album") }
  let(:high_album) { create(:album, :grounded, title: "High Album") }

  # Deliberately asymmetric ranges (not centered on 0.5): dragging to the
  # canvas's exact center (50% display) inverts to a value other than 0.5,
  # so this fixture actually distinguishes "inverted correctly" from
  # "screen fraction used directly, uninverted" — a symmetric 0.2/0.8 range
  # would invert 50% display back to 0.5 either way and prove nothing.
  before do
    create(:mood_vector, album: low_album, valence: 0.2, arousal: 0.3)
    create(:mood_vector, album: high_album, valence: 0.6, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_album, release_id: 1)
    CollectionItem.create!(user: user, album: high_album, release_id: 2)
    sign_in_as(user)
  end

  it "stretches dot positions to the full display range" do
    visit vibe_map_path

    lefts = all("[data-album-id]").map { |marker| marker[:style][/left:\s*([\d.]+)%/, 1].to_f }
    expect(lefts.min).to eq(0.0)
    expect(lefts.max).to eq(100.0)
  end

  it "inverts a dragged position back into true valence/arousal before saving an override" do
    visit vibe_map_path

    find("[data-album-id='#{low_album.id}']").drag_to(find(".vibe-map-canvas"))

    expect(page).to have_css(".vibe-map-dot--saved")

    # Dragging to the canvas center is display fraction (0.5, 0.5). Correctly
    # inverted against this fixture's ranges: valence = 0.2 + 0.5*(0.6-0.2) = 0.4,
    # arousal = 0.3 + 0.5*(0.5-0.3) = 0.4. Uninverted (buggy) code would instead
    # save the raw screen fraction (0.5, 0.5) — 0.1 away, outside this tolerance.
    override = VibeOverride.find_by(user: user, album: low_album)
    expect(override.valence).to be_within(0.05).of(0.4)
    expect(override.arousal).to be_within(0.05).of(0.4)
  end
end
