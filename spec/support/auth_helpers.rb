module AuthHelpers
  def sign_in_as(user)
    # For request specs, we authenticate by posting to the session endpoint
    # This mimics the actual login flow
    post session_path, params: { email_address: user.email_address, password: user.password }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
end
