require "rails_helper"

RSpec.describe Invitation, type: :model do
  it "is valid with an email and an inviting admin" do
    expect(build(:invitation)).to be_valid
  end

  it "requires an email" do
    invitation = build(:invitation, email: nil)
    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("can't be blank")
  end

  it "requires a validly formatted email" do
    invitation = build(:invitation, email: "not-an-email")
    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("is invalid")
  end

  it "rejects an email that already belongs to a user" do
    create(:user, email_address: "listener@example.com")
    invitation = build(:invitation, email: "listener@example.com")

    expect(invitation).not_to be_valid
    expect(invitation.errors[:email]).to include("already has an account")
  end

  it "rejects a duplicate usable invitation for the same email" do
    create(:invitation, email: "friend@example.com")
    duplicate = build(:invitation, email: "friend@example.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to include("already has a pending invitation")
  end

  it "allows a new invitation for an email whose prior invitation was revoked" do
    create(:invitation, email: "friend@example.com", revoked_at: Time.current)
    new_invitation = build(:invitation, email: "friend@example.com")

    expect(new_invitation).to be_valid
  end

  it "generates a token on creation" do
    expect(create(:invitation).token).to be_present
  end

  it "defaults to expiring 7 days from creation" do
    expect(create(:invitation).expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  describe "#usable?" do
    it "is usable when pending, unexpired, and unrevoked" do
      expect(create(:invitation)).to be_usable
    end

    it "is not usable when expired" do
      invitation = create(:invitation, expires_at: 1.minute.ago)
      expect(invitation).to be_expired
      expect(invitation).not_to be_usable
    end

    it "is not usable when revoked" do
      invitation = create(:invitation, revoked_at: Time.current)
      expect(invitation).to be_revoked
      expect(invitation).not_to be_usable
    end

    it "is not usable when already accepted" do
      invitation = create(:invitation, accepted_at: Time.current)
      expect(invitation).to be_accepted
      expect(invitation).not_to be_usable
    end
  end

  describe "#status" do
    it "is pending when unexpired, unrevoked, and unaccepted" do
      expect(create(:invitation).status).to eq("pending")
    end

    it "is expired when past its expiration" do
      expect(create(:invitation, expires_at: 1.minute.ago).status).to eq("expired")
    end

    it "is revoked when revoked, even if also expired" do
      invitation = create(:invitation, expires_at: 1.minute.ago, revoked_at: Time.current)
      expect(invitation.status).to eq("revoked")
    end

    it "is accepted when accepted, even if also revoked" do
      invitation = create(:invitation, revoked_at: Time.current, accepted_at: Time.current)
      expect(invitation.status).to eq("accepted")
    end
  end

  describe "#regenerate_link!" do
    it "issues a new token and resets the expiration so an expired invitation becomes usable again" do
      invitation = create(:invitation, expires_at: 1.minute.ago)
      old_token = invitation.token

      invitation.regenerate_link!

      expect(invitation.token).not_to eq(old_token)
      expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
      expect(invitation).to be_usable
    end
  end
end
