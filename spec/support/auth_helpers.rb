module AuthHelpers
  def sign_in_as(user)
    if RSpec.current_example.metadata[:type] == :system
      # System specs drive a real (possibly JS-capable) browser session via
      # Capybara, so we have to log in through the actual UI rather than
      # posting directly with the test's HTTP client.
      visit new_session_path
      fill_in "Enter your email address", with: user.email_address
      fill_in "Enter your password", with: user.password
      click_button "Sign in"
      # The sign-in form submits through Turbo, so the redirect away from
      # /session/new happens asynchronously. Wait for it (Capybara auto-retries
      # this matcher) before returning, otherwise callers that immediately
      # `visit` an authenticated page can race the still-in-flight login.
      expect(page).to have_no_current_path(new_session_path)
    else
      # For request specs, we authenticate by posting to the session endpoint
      # This mimics the actual login flow
      post session_path, params: { email_address: user.email_address, password: user.password }
    end
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
end
