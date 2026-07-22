require "rails_helper"

RSpec.describe Album do
  describe "#repair_youtube_link!" do
    let(:album) { create(:album, enrichment_status: :failed, youtube_url: nil) }

    it "sets the youtube_url and grounds the album" do
      album.repair_youtube_link!("https://www.youtube.com/watch?v=abc123")

      expect(album.reload).to have_attributes(
        youtube_url: "https://www.youtube.com/watch?v=abc123",
        enrichment_status: "grounded"
      )
    end

    it "accepts a youtu.be short link" do
      album.repair_youtube_link!("https://youtu.be/abc123")
      expect(album.reload.enrichment_status).to eq("grounded")
    end

    it "rejects a non-youtube url" do
      expect { album.repair_youtube_link!("https://example.com/abc") }
        .to raise_error(Album::InvalidYoutubeLinkError)
    end

    it "rejects repair when the album isn't in a failed state" do
      grounded_album = create(:album, :grounded)

      expect { grounded_album.repair_youtube_link!("https://www.youtube.com/watch?v=abc123") }
        .to raise_error(Album::InvalidTransition)
    end
  end
end
