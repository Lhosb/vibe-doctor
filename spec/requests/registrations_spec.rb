require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /registrations/:token/edit" do
    it "renders the signup form for a usable invitation" do
      invitation = create(:invitation, email: "friend@example.com")

      get edit_registration_path(invitation.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("friend@example.com")
    end

    it "redirects with an alert for an unknown token" do
      get edit_registration_path("does-not-exist")

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("invalid")
    end

    it "redirects with an alert for an expired invitation" do
      invitation = create(:invitation, expires_at: 1.minute.ago)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("expired")
    end

    it "redirects for a revoked invitation" do
      invitation = create(:invitation, revoked_at: Time.current)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
    end

    it "redirects with an alert for an already-accepted invitation" do
      invitation = create(:invitation, accepted_at: Time.current)

      get edit_registration_path(invitation.token)

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("already been used")
    end
  end

  describe "PATCH /registrations/:token" do
    it "creates the user, marks the invitation accepted, and signs the user in" do
      invitation = create(:invitation, email: "friend@example.com")

      patch registration_path(invitation.token), params: { password: "s3cret-pass", password_confirmation: "s3cret-pass" }

      expect(response).to redirect_to(root_path)
      user = User.find_by(email_address: "friend@example.com")
      expect(user).to be_present
      expect(user.authenticate("s3cret-pass")).to eq(user)
      expect(invitation.reload).to be_accepted

      get library_path
      expect(response).to have_http_status(:ok)
    end

    it "does not create a user when the passwords do not match" do
      invitation = create(:invitation, email: "friend@example.com")

      expect {
        patch registration_path(invitation.token), params: { password: "s3cret-pass", password_confirmation: "different" }
      }.not_to change(User, :count)

      expect(response).to redirect_to(edit_registration_path(invitation.token))
      expect(invitation.reload).not_to be_accepted
    end
  end
end
