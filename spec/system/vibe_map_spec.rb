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

  it "renders a point at the album's valence/arousal position and navigates to the album when clicked" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.click

    expect(page).to have_current_path(album_path(album))
  end

  it "posts an override with the new position and preserves other mood values on drag" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{album.id}']")
    expect(page).to have_current_path(vibe_map_path)

    override = VibeOverride.find_by(user: user, album: album)
    expect(override.source).to eq("vibe_map")
    expect(override.danceability).to eq(0.2)
    expect(override.mood_acoustic).to eq(0.9)
    expect(override.mood_relaxed).to eq(0.1)
    expect(override.mood_happy).to eq(0.8)
  end
end
