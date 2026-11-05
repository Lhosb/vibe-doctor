require "rails_helper"

RSpec.describe "Discogs connection settings", type: :request do
  let(:user) { create(:user, discogs_username: "listener", discogs_token: "old-token") }

  before { sign_in_as(user) }

  describe "GET /discogs_connection/edit" do
    it "renders the form pre-filled with the current username and token" do
      get edit_discogs_connection_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="listener"')
      expect(response.body).to include('value="old-token"')
    end
  end

  describe "PATCH /discogs_connection" do
    it "saves the new username/token and re-enqueues the sync job" do
      expect {
        patch discogs_connection_path, params: { discogs_username: "newname", discogs_token: "new-token" }
      }.to have_enqueued_job(SyncDiscogsCollectionJob).with(user)

      expect(response).to redirect_to(library_path)
      user.reload
      expect(user.discogs_username).to eq("newname")
      expect(user.discogs_token).to eq("new-token")
    end
  end

  describe "POST /discogs_connection/resync" do
    it "enqueues a sync job for the current user without requiring credentials" do
      expect {
        post resync_discogs_connection_path
      }.to have_enqueued_job(SyncDiscogsCollectionJob).with(user)

      expect(response).to redirect_to(library_path)
      expect(flash[:notice]).to eq("Discogs sync started.")
    end
  end
end
