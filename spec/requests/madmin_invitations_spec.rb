require "rails_helper"

RSpec.describe "Madmin: invitations", type: :request do
  let(:admin) { create(:user, admin: true) }

  before { sign_in_as(admin) }

  describe "creating an invitation" do
    it "creates an invitation for the given email and records the inviting admin" do
      post "/admin/invitations", params: { invitation: { email: "friend@example.com" } }

      invitation = Invitation.last
      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.email).to eq("friend@example.com")
      expect(invitation.invited_by).to eq(admin)
    end

    it "rejects an email that already belongs to a user" do
      create(:user, email_address: "listener@example.com")

      expect {
        post "/admin/invitations", params: { invitation: { email: "listener@example.com" } }
      }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a duplicate usable invitation for the same email" do
      create(:invitation, invited_by: admin, email: "friend@example.com")

      expect {
        post "/admin/invitations", params: { invitation: { email: "friend@example.com" } }
      }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows a copyable signup link on the invitation's show page" do
      invitation = create(:invitation, invited_by: admin, email: "friend@example.com")

      get "/admin/invitations/#{invitation.id}"

      expect(response.body).to include(edit_registration_path(invitation.token))
    end
  end

  describe "regenerating a link" do
    it "issues a new token and extends the expiration" do
      invitation = create(:invitation, invited_by: admin, expires_at: 1.minute.ago)
      old_token = invitation.token

      post "/admin/invitations/#{invitation.id}/regenerate_link"

      invitation.reload
      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.token).not_to eq(old_token)
      expect(invitation).to be_usable
    end
  end

  describe "revoking an invitation" do
    it "marks the invitation revoked so it can no longer be used" do
      invitation = create(:invitation, invited_by: admin)

      post "/admin/invitations/#{invitation.id}/revoke"

      expect(response).to redirect_to("/admin/invitations/#{invitation.id}")
      expect(invitation.reload).to be_revoked
    end
  end

  it "forbids a non-admin from managing invitations" do
    sign_in_as(create(:user, admin: false))

    get "/admin/invitations"

    expect(response).to have_http_status(:forbidden)
  end
end
