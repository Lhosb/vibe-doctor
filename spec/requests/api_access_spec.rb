require "rails_helper"

RSpec.describe "API access settings", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "GET /api_access/edit" do
    it "renders the current token" do
      get edit_api_access_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.api_token)
    end

    it "backfills a token for a user who doesn't have one yet" do
      user.update_column(:api_token, nil)

      get edit_api_access_path

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.api_token).to be_present
      expect(response.body).to include(user.api_token)
    end
  end

  describe "POST /api_access/regenerate" do
    it "changes the token and redirects with a notice" do
      old_token = user.api_token

      post regenerate_api_access_path

      expect(response).to redirect_to(edit_api_access_path)
      expect(flash[:notice]).to eq("API token regenerated.")
      user.reload
      expect(user.api_token).not_to eq(old_token)
    end
  end
end
