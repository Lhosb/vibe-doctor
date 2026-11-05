require "rails_helper"

RSpec.describe Album, type: :model do
  it "is valid with a master_id and title" do
    expect(Album.new(master_id: 1, title: "Nevermind")).to be_valid
  end

  it "requires a unique master_id" do
    Album.create!(master_id: 1, title: "Nevermind")
    duplicate = Album.new(master_id: 1, title: "Nevermind (reissue)")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:master_id]).to include("has already been taken")
  end

  it "starts in the pending enrichment state" do
    album = Album.create!(master_id: 1, title: "Nevermind")
    expect(album).to be_pending
  end

  it "transitions from pending to matching_audio to extracting_features to grounded" do
    album = Album.create!(master_id: 1, title: "Nevermind")
    album.start_matching!
    expect(album).to be_matching_audio
    album.start_extracting!
    expect(album).to be_extracting_features
    album.ground!
    expect(album).to be_grounded
  end

  it "recovers from failed through matching_audio to grounded" do
    album = Album.create!(master_id: 1, title: "Nevermind")
    album.fail_enrichment!

    album.start_matching!
    expect(album).to be_matching_audio
    album.start_extracting!
    album.ground!

    expect(album).to be_grounded
  end

  it "raises on an invalid transition" do
    album = Album.create!(master_id: 1, title: "Nevermind")
    expect { album.ground! }.to raise_error(Album::InvalidTransition, "cannot transition to grounded from pending")
  end

  describe "#reset_enrichment!" do
    it "forces a grounded album back to pending, bypassing ENRICHMENT_TRANSITIONS" do
      album = Album.create!(master_id: 1, title: "Nevermind").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)

      album.reset_enrichment!

      expect(album).to be_pending
    end
  end

  describe ".needing_enrichment" do
    it "includes pending and failed albums but not albums mid-flight or grounded" do
      pending = Album.create!(master_id: 1, title: "Pending")
      failed = Album.create!(master_id: 2, title: "Failed").tap(&:start_matching!).tap(&:fail_enrichment!)
      matching = Album.create!(master_id: 3, title: "Matching").tap(&:start_matching!)
      grounded = Album.create!(master_id: 4, title: "Grounded").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)

      expect(Album.needing_enrichment).to contain_exactly(pending, failed)
      expect(Album.needing_enrichment).not_to include(matching, grounded)
    end
  end
end
