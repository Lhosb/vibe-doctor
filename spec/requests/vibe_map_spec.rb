require "rails_helper"

RSpec.describe "GET /vibe_map", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  def dots_from(response_body)
    html = Nokogiri::HTML5.parse(response_body)
    json = html.at_css("[data-library-vibe-map-dots-value]")["data-library-vibe-map-dots-value"]
    JSON.parse(json)
  end

  it "shows only the current user's grounded albums" do
    grounded = create(:album, :grounded)
    create(:mood_vector, album: grounded, valence: 0.7, arousal: 0.3)
    CollectionItem.create!(user: user, album: grounded, release_id: 1)

    get "/vibe_map"

    expect(response).to have_http_status(:ok)
    expect(dots_from(response.body).map { |d| d["id"] }).to include(grounded.id)
  end

  it "excludes another user's collection albums" do
    other_user = create(:user)
    other_album = create(:album, :grounded)
    create(:mood_vector, album: other_album)
    CollectionItem.create!(user: other_user, album: other_album, release_id: 2)

    get "/vibe_map"

    expect(dots_from(response.body).map { |d| d["id"] }).not_to include(other_album.id)
  end

  it "excludes ungrounded albums from the current user's own collection" do
    pending_album = create(:album)
    CollectionItem.create!(user: user, album: pending_album, release_id: 3)

    get "/vibe_map"

    expect(dots_from(response.body).map { |d| d["id"] }).not_to include(pending_album.id)
  end

  it "includes each dot's raw valence/arousal and mood fields, for the client to render and drag-override" do
    grounded = create(:album, :grounded, title: "Kind of Blue", genres: [ "Jazz" ])
    create(
      :mood_vector, album: grounded,
      valence: 0.7, arousal: 0.3, danceability: 0.2, mood_acoustic: 0.9, mood_relaxed: 0.1, mood_happy: 0.8
    )
    CollectionItem.create!(user: user, album: grounded, release_id: 15)

    get "/vibe_map"

    dot = dots_from(response.body).find { |d| d["id"] == grounded.id }
    expect(dot["title"]).to eq("Kind of Blue")
    expect(dot["href"]).to eq(Rails.application.routes.url_helpers.album_path(grounded))
    expect(dot["valence"]).to eq(0.7)
    expect(dot["arousal"]).to eq(0.3)
    expect(dot["genre"]).to eq("Jazz")
    expect(dot["danceability"]).to eq(0.2)
    expect(dot["mood_acoustic"]).to eq(0.9)
    expect(dot["mood_relaxed"]).to eq(0.1)
    expect(dot["mood_happy"]).to eq(0.8)
  end
end

RSpec.describe "GET /vibe_map/global", type: :request do
  def dots_from(response_body)
    html = Nokogiri::HTML5.parse(response_body)
    json = html.at_css("[data-library-vibe-map-dots-value]")["data-library-vibe-map-dots-value"]
    JSON.parse(json)
  end

  it "forbids access to a non-admin user" do
    sign_in_as(create(:user, admin: false))

    get "/vibe_map/global"

    expect(response).to have_http_status(:forbidden)
  end

  it "shows grounded albums across all users' collections to an admin" do
    sign_in_as(create(:user, admin: true))
    other_user = create(:user)
    grounded = create(:album, :grounded)
    create(:mood_vector, album: grounded)
    CollectionItem.create!(user: other_user, album: grounded, release_id: 1)

    get "/vibe_map/global"

    expect(response).to have_http_status(:ok)
    expect(dots_from(response.body).map { |d| d["id"] }).to include(grounded.id)
  end
end
