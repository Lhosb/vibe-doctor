require "rails_helper"

RSpec.describe "Registration", type: :system do
  it "lets an invited user set a password and creates their account" do
    invitation = create(:invitation, email: "friend@example.com")

    visit edit_registration_path(invitation.token)

    fill_in "Choose a password", with: "s3cret-pass"
    fill_in "Repeat password", with: "s3cret-pass"
    click_button "Create account"

    expect(page).to have_content("Library")
    expect(page).to have_content("friend@example.com")
  end
end
