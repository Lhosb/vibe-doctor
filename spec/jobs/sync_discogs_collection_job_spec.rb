require "rails_helper"

RSpec.describe SyncDiscogsCollectionJob, type: :job do
  let(:user) { create(:user, discogs_username: "listener", discogs_token: "test-token-abc") }

  before do
    stub_request(:get, "https://api.discogs.com/users/listener/collection/folders/0/releases")
      .with(query: { page: "1", per_page: "100" }, headers: { "Authorization" => "Discogs token=test-token-abc" })
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          pagination: { page: 1, pages: 2, per_page: 100, items: 2 },
          releases: [
            {
              id: 111,
              instance_id: 9001,
              basic_information: {
                id: 111,
                master_id: 500,
                title: "Album One",
                year: 1999,
                genres: [ "Rock" ],
                styles: [ "Alternative Rock" ],
                artists: [ { name: "Band One" } ]
              }
            }
          ]
        }.to_json
      )

    stub_request(:get, "https://api.discogs.com/users/listener/collection/folders/0/releases")
      .with(query: { page: "2", per_page: "100" }, headers: { "Authorization" => "Discogs token=test-token-abc" })
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          pagination: { page: 2, pages: 2, per_page: 100, items: 2 },
          releases: [
            {
              id: 222,
              instance_id: 9002,
              basic_information: {
                id: 222,
                master_id: 0,
                title: "Obscure Pressing",
                year: 2005,
                genres: [ "Jazz" ],
                styles: [ "Fusion" ],
                artists: [ { name: "Solo Artist" } ]
              }
            }
          ]
        }.to_json
      )
  end

  it "creates a CollectionItem and canonical Album per release across pages" do
    described_class.perform_now(user)

    expect(CollectionItem.where(user: user).count).to eq(2)

    canonical = Album.find_by(master_id: 500)
    expect(canonical.title).to eq("Album One")
    expect(canonical.synthetic_master_id).to eq(false)
    expect(canonical.artists).to eq([ "Band One" ])

    synthetic = Album.find_by(master_id: 222)
    expect(synthetic.title).to eq("Obscure Pressing")
    expect(synthetic.synthetic_master_id).to eq(true)
  end

  it "is idempotent when run twice" do
    described_class.perform_now(user)
    described_class.perform_now(user)

    expect(CollectionItem.where(user: user).count).to eq(2)
    expect(Album.count).to eq(2)
  end

  it "enqueues EnrichAlbumJob only for newly-created albums, not ones already known" do
    existing_album = Album.create!(master_id: 500, title: "Album One", synthetic_master_id: false)

    expect { described_class.perform_now(user) }.to have_enqueued_job(EnrichAlbumJob).with(existing_album).exactly(0).times
    expect(EnrichAlbumJob).to have_been_enqueued.with(Album.find_by(master_id: 222)).once
  end
end
