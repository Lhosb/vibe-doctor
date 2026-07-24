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

  it "rescales dot positions to fill the display range when a spread exists" do
    low = create(:album, :grounded, title: "Low")
    high = create(:album, :grounded, title: "High")
    create(:mood_vector, album: low, valence: 0.2, arousal: 0.2)
    create(:mood_vector, album: high, valence: 0.8, arousal: 0.8)
    CollectionItem.create!(user: user, album: low, release_id: 10)
    CollectionItem.create!(user: user, album: high, release_id: 11)

    get "/vibe_map"

    expect(response.body).to match(/left:\s*0\.0%/)
    expect(response.body).to match(/left:\s*100\.0%/)
  end

  it "rescales only the axis that actually has spread" do
    low_valence = create(:album, :grounded)
    high_valence = create(:album, :grounded)
    create(:mood_vector, album: low_valence, valence: 0.3, arousal: 0.5)
    create(:mood_vector, album: high_valence, valence: 0.9, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_valence, release_id: 12)
    CollectionItem.create!(user: user, album: high_valence, release_id: 13)

    get "/vibe_map"

    # valence has real spread (0.3..0.9) -> rescaled to fill 0%..100%
    expect(response.body).to match(/left:\s*0\.0%/)
    expect(response.body).to match(/left:\s*100\.0%/)
    # arousal is identical (0.5) for both -> no rescaling, raw value used: 100 - 0.5*100 = 50.0
    expect(response.body).to match(/top:\s*50\.0%/)
  end

  it "exposes the valence/arousal range as data attributes for the drag controller" do
    low = create(:album, :grounded)
    high = create(:album, :grounded)
    create(:mood_vector, album: low, valence: 0.2, arousal: 0.25)
    create(:mood_vector, album: high, valence: 0.8, arousal: 0.75)
    CollectionItem.create!(user: user, album: low, release_id: 13)
    CollectionItem.create!(user: user, album: high, release_id: 14)

    get "/vibe_map"

    expect(response.body).to include(%(data-library-vibe-map-valence-min-value="0.2"))
    expect(response.body).to include(%(data-library-vibe-map-valence-max-value="0.8"))
    expect(response.body).to include(%(data-library-vibe-map-arousal-min-value="0.25"))
    expect(response.body).to include(%(data-library-vibe-map-arousal-max-value="0.75"))
  end

  it "shows the album title as an always-on label" do
    grounded = create(:album, :grounded, title: "Kind of Blue")
    create(:mood_vector, album: grounded, valence: 0.5, arousal: 0.5)
    CollectionItem.create!(user: user, album: grounded, release_id: 15)

    get "/vibe_map"

    expect(response.body).to include(%(class="vibe-map-label))
    expect(response.body).to include("Kind of Blue")
  end
end
