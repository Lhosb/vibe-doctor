require "rails_helper"

RSpec.describe User, type: :model do
  it "is valid with an email address and password" do
    expect(build(:user)).to be_valid
  end

  it "requires an email address" do
    user = build(:user, email_address: nil)
    expect(user).not_to be_valid
    expect(user.errors[:email_address]).to include("can't be blank")
  end

  it "requires a unique email address" do
    create(:user, email_address: "listener@example.com")
    duplicate = build(:user, email_address: "listener@example.com")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email_address]).to include("has already been taken")
  end

  it "authenticates with the correct password" do
    user = create(:user, password: "s3cret-pass")
    expect(User.authenticate_by(email_address: user.email_address, password: "s3cret-pass")).to eq(user)
  end
end
