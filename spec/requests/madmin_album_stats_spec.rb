require "rails_helper"

RSpec.describe "Madmin: per-album recommendation stats", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:album) { create(:album, :grounded) }

  before { sign_in_as(admin) }

  it "renders aggregated recommendation stats for the album" do
    create(:recommendation_event, album: album, outcome: "good", final_score: 0.9)

    get "/admin/albums/#{album.id}/recommendation_stats"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total recommended: 1")
    expect(response.body).to include("Good: 1")
  end
end
