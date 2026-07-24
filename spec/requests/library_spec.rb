require "rails_helper"

RSpec.describe "GET /library", type: :request do
  let(:user) { create(:user, discogs_username: "listener") }

  before { sign_in_as(user) }

  it "lists the current user's collection as a table sorted by artist then title" do
    zebra = create(:album, artists: [ "Zebra Band" ], title: "Zebra Album", genres: [ "Rock" ], year: 2010, enrichment_status: "pending")
    apple = create(:album, artists: [ "Apple Band" ], title: "Apple Album", genres: [ "Jazz" ], year: 2015, enrichment_status: "grounded")
    CollectionItem.create!(user: user, album: zebra, release_id: 1)
    CollectionItem.create!(user: user, album: apple, release_id: 2)

    get "/library"

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Apple Album")).to be < response.body.index("Zebra Album")
    expect(response.body).to include("Jazz")
    expect(response.body).to include("Rock")
    expect(response.body).to include("2010")
    expect(response.body).to include("2015")
    expect(response.body).to include("Grounded")
    expect(response.body).to include("Pending")
  end

  it "shows the Connect Discogs prompt when no Discogs account is linked" do
    unlinked_user = create(:user, discogs_username: nil)
    sign_in_as(unlinked_user)

    get "/library"

    expect(response.body).to include("Connect Discogs")
  end

  it "shows nav links positioned Library < Vibe Map < Recommend < Feedback" do
    get "/library"

    body = response.body
    library_link_index = body.index(%(href="/library"))
    vibe_map_link_index = body.index(%(href="/vibe_map"))
    recommend_link_index = body.index(%(href="/recommend"))
    feedback_link_index = body.index(%(href="/feedback"))

    expect(vibe_map_link_index).to be_present
    expect(recommend_link_index).to be_present
    expect(library_link_index).to be < vibe_map_link_index
    expect(vibe_map_link_index).to be < recommend_link_index
    expect(recommend_link_index).to be < feedback_link_index
  end
end
