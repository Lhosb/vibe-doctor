require "rails_helper"

RSpec.describe "Madmin: repair YouTube link", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:album) { create(:album, enrichment_status: :failed, youtube_url: nil) }

  before { sign_in_as(admin) }

  it "repairs the youtube link and grounds the album" do
    post "/admin/albums/#{album.id}/repair_youtube_link", params: { youtube_url: "https://www.youtube.com/watch?v=abc123" }

    expect(response).to redirect_to("/admin/albums/#{album.id}")
    expect(album.reload).to have_attributes(
      youtube_url: "https://www.youtube.com/watch?v=abc123",
      enrichment_status: "grounded"
    )
  end

  it "redirects with an alert on an invalid link" do
    post "/admin/albums/#{album.id}/repair_youtube_link", params: { youtube_url: "https://example.com/abc" }

    expect(response).to redirect_to("/admin/albums/#{album.id}")
    expect(album.reload.youtube_url).to be_nil
  end
end
