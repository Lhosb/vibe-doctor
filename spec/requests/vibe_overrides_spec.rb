require "rails_helper"

RSpec.describe "POST /albums/:album_id/vibe_override", type: :request do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded) }

  before { sign_in_as(user) }

  it "creates an override from the album detail controls" do
    post "/albums/#{album.id}/vibe_override", params: {
      valence: 0.3,
      arousal: 0.4,
      danceability: 0.5,
      mood_acoustic: 0.6,
      mood_relaxed: 0.7,
      mood_happy: 0.8,
      genre: "Ambient",
      source: "album_detail"
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("album_id" => album.id, "source" => "album_detail")
    expect(VibeOverride.find_by(user: user, album: album)).to have_attributes(source: "album_detail", genre: "Ambient")
  end

  it "returns 400 when a required mood attribute is missing" do
    post "/albums/#{album.id}/vibe_override", params: { valence: 0.3, source: "album_detail" }
    expect(response).to have_http_status(:bad_request)
  end

  it "returns 404 for an unknown album" do
    post "/albums/-1/vibe_override", params: {
      valence: 0.3,
      arousal: 0.4,
      danceability: 0.5,
      mood_acoustic: 0.6,
      mood_relaxed: 0.7,
      mood_happy: 0.8,
      source: "album_detail"
    }

    expect(response).to have_http_status(:not_found)
  end
end
