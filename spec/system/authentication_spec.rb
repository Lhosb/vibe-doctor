require "rails_helper"

RSpec.describe "Authentication", type: :system do
  it "redirects unauthenticated visitors to the login page" do
    visit root_path
    expect(page).to have_current_path(new_session_path)
  end

  it "logs an existing user in and shows the Library page" do
    user = create(:user, email_address: "listener@example.com", password: "s3cret-pass")

    visit new_session_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: "s3cret-pass"
    click_button "Sign in"

    expect(page).to have_content("Library")
    expect(page).to have_content("listener@example.com")
  end
end
