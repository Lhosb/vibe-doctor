require "rails_helper"

RSpec.describe "POST /recommend/feedback with API token authentication", type: :request do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded) }
  let(:event) { create(:recommendation_event, user: user, album: album) }

  it "returns the outcome contract for a valid bearer token, with no cookie session" do
    post "/recommend/feedback",
      params: { recommendation_event_id: event.id, outcome: "good" },
      headers: { "Authorization" => "Bearer #{user.api_token}" },
      as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["outcome"]).to eq("good")

    event.reload
    expect(event.outcome).to eq("good")
  end
end
