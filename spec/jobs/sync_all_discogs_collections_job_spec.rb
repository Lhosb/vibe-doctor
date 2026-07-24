require "rails_helper"

RSpec.describe SyncAllDiscogsCollectionsJob, type: :job do
  let!(:connected_user) { create(:user, discogs_username: "listener", discogs_token: "test-token-abc") }
  let!(:disconnected_user) { create(:user, discogs_username: nil, discogs_token: nil) }

  it "enqueues SyncDiscogsCollectionJob only for users with a discogs_token" do
    expect {
      described_class.perform_now
    }.to have_enqueued_job(SyncDiscogsCollectionJob).with(connected_user).exactly(1).times

    expect(SyncDiscogsCollectionJob).not_to have_been_enqueued.with(disconnected_user)
  end
end
