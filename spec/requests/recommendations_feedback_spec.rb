require "rails_helper"

RSpec.describe "POST /recommend/feedback", type: :request do
  let(:user) { create(:user, password: "s3cret-pass") }
  let(:album) { create(:album, :grounded) }
  let(:event) { create(:recommendation_event, user: user, album: album) }

  before do
    post session_path, params: { email_address: user.email_address, password: "s3cret-pass" }
  end

  it "returns the outcome contract on success" do
    post "/recommend/feedback", params: { recommendation_event_id: event.id, outcome: "good" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to contain_exactly("recommendation_event_id", "outcome", "album_affinity_score")
    expect(body["outcome"]).to eq("good")
    expect(body["album_affinity_score"]).to eq(0.15)
  end

  it "returns 422 for an invalid outcome" do
    post "/recommend/feedback", params: { recommendation_event_id: event.id, outcome: "meh" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 422 when the event is no longer pending" do
    event.apply_outcome!("good")

    post "/recommend/feedback", params: { recommendation_event_id: event.id, outcome: "bad" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 404 for an unknown event" do
    post "/recommend/feedback", params: { recommendation_event_id: -1, outcome: "good" }
    expect(response).to have_http_status(:not_found)
  end

  it "returns 400 when outcome is missing" do
    post "/recommend/feedback", params: { recommendation_event_id: event.id }
    expect(response).to have_http_status(:bad_request)
  end

  it "does not let another user mutate someone else's recommendation event (IDOR)" do
    owning_users_event = event
    other_user = create(:user, password: "s3cret-pass")

    # Sign out the owning user and sign in as a different user.
    delete session_path
    post session_path, params: { email_address: other_user.email_address, password: "s3cret-pass" }

    post "/recommend/feedback", params: { recommendation_event_id: owning_users_event.id, outcome: "good" }

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "recommendation event not found")

    owning_users_event.reload
    expect(owning_users_event.outcome).to eq("pending")
    expect(AlbumAffinity.find_by(user: user, album: album)).to be_nil
  end
end
