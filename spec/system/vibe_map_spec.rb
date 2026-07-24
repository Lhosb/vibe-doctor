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
end
