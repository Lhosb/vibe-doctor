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

  it "raises on an invalid transition" do
    album = Album.create!(master_id: 1, title: "Nevermind")
    expect { album.ground! }.to raise_error(Album::InvalidTransition, "cannot transition to grounded from pending")
  end
end
