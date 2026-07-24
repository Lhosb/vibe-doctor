require "rails_helper"

RSpec.describe "GET /albums/:id", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "shows year, genres, and styles in the header" do
    album = create(:album, :grounded, title: "Kind of Blue", year: 1959, genres: [ "Jazz" ], styles: [ "Modal" ])

    get album_path(album)

    expect(response.body).to include("1959")
    expect(response.body).to include("Jazz")
    expect(response.body).to include("Modal")
  end

  it "shows a mood breakdown for all six dimensions" do
    album = create(:album, :grounded)
    create(
      :mood_vector, album: album,
      valence: 0.62, arousal: 0.41, danceability: 0.73, mood_acoustic: 0.15, mood_relaxed: 0.28, mood_happy: 0.55
    )

    get album_path(album)

    expect(response.body).to include("0.62")
    expect(response.body).to include("0.41")
    expect(response.body).to include("0.73")
    expect(response.body).to include("0.15")
    expect(response.body).to include("0.28")
    expect(response.body).to include("0.55")
  end

  it "omits the mood breakdown when the album has no mood data" do
    album = create(:album)

    get album_path(album)

    expect(response.body).not_to include("Mood breakdown")
  end
end
