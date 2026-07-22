require "rails_helper"

RSpec.describe "GET /feedback", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "renders the next pending recommendation as a card" do
    event = create(:recommendation_event, user: user, outcome: "pending")

    get "/feedback"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(event.album.title)
    expect(response.body).to include(%(data-feedback-event-id-value="#{event.id}"))
  end

  it "shows the empty state when there is nothing pending" do
    get "/feedback"

    expect(response.body).to include("You're all caught up!")
  end
end

RSpec.describe "POST /feedback", type: :request do
  let(:user) { create(:user) }
  let(:event) { create(:recommendation_event, user: user, outcome: "pending") }

  before { sign_in_as(user) }

  it "updates the current user's pending event outcome" do
    post "/feedback", params: { recommendation_event_id: event.id, outcome: "good" }

    expect(response).to have_http_status(:found)
    expect(event.reload.outcome).to eq("good")
  end

  it "returns not found for another user's event id" do
    other_user = create(:user)
    other_event = create(:recommendation_event, user: other_user, outcome: "pending")

    post "/feedback", params: { recommendation_event_id: other_event.id, outcome: "good" }

    expect(response).to have_http_status(:not_found)
    expect(other_event.reload.outcome).to eq("pending")
  end
end
