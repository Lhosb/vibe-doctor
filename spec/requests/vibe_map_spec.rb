require "rails_helper"

RSpec.describe "GET /vibe_map", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "shows only the current user's grounded albums" do
    grounded = create(:album, :grounded)
    create(:mood_vector, album: grounded, valence: 0.7, arousal: 0.3)
    CollectionItem.create!(user: user, album: grounded, release_id: 1)

    get "/vibe_map"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-album-id="#{grounded.id}"))
  end

  it "excludes another user's collection albums" do
    other_user = create(:user)
    other_album = create(:album, :grounded)
    create(:mood_vector, album: other_album)
    CollectionItem.create!(user: other_user, album: other_album, release_id: 2)

    get "/vibe_map"

    expect(response.body).not_to include(%(data-album-id="#{other_album.id}"))
  end

  it "excludes ungrounded albums from the current user's own collection" do
    pending_album = create(:album)
    CollectionItem.create!(user: user, album: pending_album, release_id: 3)

    get "/vibe_map"

    expect(response.body).not_to include(%(data-album-id="#{pending_album.id}"))
  end
end
