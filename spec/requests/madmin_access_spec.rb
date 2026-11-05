require "rails_helper"

RSpec.describe "Madmin admin panel", type: :request do
  it "forbids access to a non-admin user" do
    sign_in_as(create(:user, admin: false))

    get "/admin"

    expect(response).to have_http_status(:forbidden)
  end

  it "allows access to an admin user" do
    sign_in_as(create(:user, admin: true))

    get "/admin"

    expect(response).to have_http_status(:ok)
  end

  it "forbids access via a bearer token, even for an admin user" do
    admin = create(:user, admin: true)

    get "/admin", headers: { "Authorization" => "Bearer #{admin.api_token}" }

    expect(response).to have_http_status(:forbidden)
  end
end
