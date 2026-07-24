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

  it "still overrides (not pans) when dragging a point with zoom/pan enabled" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{album.id}']")
    expect(VibeOverride.find_by(user: user, album: album)).to be_present
  end

  it "does not create an override when dragging on empty canvas (pan, not point-drag)" do
    visit vibe_map_path

    canvas = find('[data-library-vibe-map-target="map"]')
    canvas.drag_to(canvas) # drag from/to the same empty-canvas element -- not a data point

    expect(VibeOverride.find_by(user: user, album: album)).to be_nil
  end

  it "lists each distinct genre in the legend and hides that genre's points on click" do
    rock_album = create(:album, :grounded, title: "Rock Album", genres: [ "Rock" ])
    create(:mood_vector, album: rock_album, valence: 0.2, arousal: 0.8)
    CollectionItem.create!(user: user, album: rock_album, release_id: 2)

    visit vibe_map_path

    expect(page).to have_text("Jazz")
    expect(page).to have_text("Rock")

    # both points are present and clickable before filtering
    find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    find_vibe_map_point(rock_album, valence: 0.2, arousal: 0.8)

    all("text", text: "Rock").find { |el| el.text == "Rock" }.click # toggle the Rock series off via the legend

    expect(page).to have_no_css("[data-album-id='#{rock_album.id}']", wait: 2)
  end

  it "rescales axes to the remaining points when a genre is filtered out via the legend" do
    rock_album = create(:album, :grounded, title: "Rock Album", genres: [ "Rock" ])
    create(:mood_vector, album: rock_album, valence: 0.2, arousal: 0.8)
    CollectionItem.create!(user: user, album: rock_album, release_id: 2)

    visit vibe_map_path

    pixel_before = page.evaluate_script(<<~JS)
      window.document.querySelector('[data-library-vibe-map-target="map"]')
        .__echartsInstance.convertToPixel({xAxisIndex: 0, yAxisIndex: 0}, [0.7, 0.3])
    JS

    all("text", text: "Rock").find { |el| el.text == "Rock" }.click

    pixel_after = page.evaluate_script(<<~JS)
      window.document.querySelector('[data-library-vibe-map-target="map"]')
        .__echartsInstance.convertToPixel({xAxisIndex: 0, yAxisIndex: 0}, [0.7, 0.3])
    JS

    expect(pixel_after).not_to eq(pixel_before)
  end
end
