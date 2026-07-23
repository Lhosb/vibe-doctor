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

  describe "the show page's repair form" do
    it "renders a real, editable text input for youtube_url defaulting to blank when the album has none" do
      get "/admin/albums/#{album.id}"

      input = extract_youtube_url_input(response.body)
      expect(input).not_to be_nil, "expected a non-hidden <input name=\"youtube_url\"> tag in the response body"
      expect(input[:type]).not_to eq("hidden")
      expect(input[:value].to_s).to eq("")
    end

    it "defaults the input's value to the album's existing youtube_url, not a hardcoded placeholder" do
      existing = create(:album, enrichment_status: :failed, youtube_url: "https://www.youtube.com/watch?v=real123")

      get "/admin/albums/#{existing.id}"

      input = extract_youtube_url_input(response.body)
      expect(input).not_to be_nil, "expected a non-hidden <input name=\"youtube_url\"> tag in the response body"
      expect(input[:type]).not_to eq("hidden")
      expect(input[:value]).to eq("https://www.youtube.com/watch?v=real123")
      expect(input[:value]).not_to eq("https://www.youtube.com/watch?v=abc123")
    end
  end

  def extract_youtube_url_input(body)
    body.scan(/<input\b[^>]*>/i).map { |tag| parse_input_tag(tag) }
      .find { |attrs| attrs && attrs[:name] == "youtube_url" }
  end

  def parse_input_tag(tag)
    attrs = {}
    tag.scan(/(\w[\w-]*)=("([^"]*)"|'([^']*)')/).each do |name, _, dq, sq|
      attrs[name.to_sym] = dq || sq || ""
    end
    attrs
  end
end
