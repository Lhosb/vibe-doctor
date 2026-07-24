require "rails_helper"

RSpec.describe "Vibe Map", type: :system, js: true do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, title: "Kind of Blue", genres: [ "Jazz" ]) }

  before do
    create(
      :mood_vector, album: album,
      valence: 0.7, arousal: 0.3, danceability: 0.2, mood_acoustic: 0.9, mood_relaxed: 0.1, mood_happy: 0.8
    )
    CollectionItem.create!(user: user, album: album, release_id: 1)
    sign_in_as(user)
  end

  it "renders a dot at the position derived from the album's mood values" do
    visit vibe_map_path

    dot = find(".vibe-map-dot")
    left = dot[:style][/left:\s*([\d.]+)%/, 1].to_f
    top = dot[:style][/top:\s*([\d.]+)%/, 1].to_f
    expect(left).to eq(70)
    expect(top).to eq(70)
  end

  it "navigates to the album when a dot is clicked without dragging" do
    visit vibe_map_path

    find(".vibe-map-dot").click

    expect(page).to have_current_path(album_path(album))
  end

  it "posts an override with the new position and preserves the other mood values on drag" do
    visit vibe_map_path

    find(".vibe-map-dot").drag_to(find(".vibe-map-canvas"))

    expect(page).to have_css(".vibe-map-dot--saved")

    override = VibeOverride.find_by(user: user, album: album)
    expect(override.source).to eq("vibe_map")
    expect(override.valence).to be_within(0.05).of(0.5)
    expect(override.arousal).to be_within(0.05).of(0.5)
    expect(override.danceability).to eq(0.2)
    expect(override.mood_acoustic).to eq(0.9)
    expect(override.mood_relaxed).to eq(0.1)
    expect(override.mood_happy).to eq(0.8)
  end
end
