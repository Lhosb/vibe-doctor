require "rails_helper"

RSpec.describe Embedding, type: :model do
  let(:album) { Album.create!(master_id: 1, title: "Nevermind") }

  it "requires an album" do
    embedding = Embedding.new(sonic: Array.new(1536, 0.1))
    expect(embedding).not_to be_valid
  end

  it "stores and retrieves a 1536-dimension vector per facet" do
    embedding = Embedding.create!(album: album, sonic: Array.new(1536, 0.25))
    reloaded = embedding.reload
    expect(reloaded.sonic.length).to eq(1536)
    expect(reloaded.sonic.first).to eq(0.25)
    expect(reloaded.emotional).to be_nil
  end
end
