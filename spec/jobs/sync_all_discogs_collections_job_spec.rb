require "rails_helper"

RSpec.describe SyncAllDiscogsCollectionsJob, type: :job do
  let!(:connected_user) { create(:user, discogs_username: "listener", discogs_token: "test-token-abc") }
  let!(:disconnected_user) { create(:user, discogs_username: nil, discogs_token: nil) }
  let!(:token_only_user) { create(:user, discogs_username: nil, discogs_token: "test-token-orphan") }

  it "enqueues SyncDiscogsCollectionJob only for users with a discogs_token" do
    expect {
      described_class.perform_now
    }.to have_enqueued_job(SyncDiscogsCollectionJob).with(connected_user).exactly(1).times

    expect(SyncDiscogsCollectionJob).not_to have_been_enqueued.with(disconnected_user)
  end

  it "does not enqueue SyncDiscogsCollectionJob for a user with a discogs_token but no discogs_username" do
    described_class.perform_now

    expect(SyncDiscogsCollectionJob).not_to have_been_enqueued.with(token_only_user)
  end
end
