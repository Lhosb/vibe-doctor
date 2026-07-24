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

  it "shows the requested event when it belongs to the current user and is still pending" do
    create(:recommendation_event, user: user, album: create(:album, title: "Older Album"), outcome: "pending")
    target_event = create(:recommendation_event, user: user, album: create(:album, title: "Target Album"), outcome: "pending")

    get "/feedback", params: { recommendation_event_id: target_event.id }

    expect(response.body).to include("Target Album")
    expect(response.body).not_to include("Older Album")
  end

  it "falls back to the oldest pending event for another user's event id" do
    create(:recommendation_event, user: user, album: create(:album, title: "Own Album"), outcome: "pending")
    other_user = create(:user)
    other_event = create(:recommendation_event, user: other_user, album: create(:album, title: "Other Album"), outcome: "pending")

    get "/feedback", params: { recommendation_event_id: other_event.id }

    expect(response.body).to include("Own Album")
    expect(response.body).not_to include("Other Album")
  end

  it "falls back to the oldest pending event for an already-actioned event id" do
    create(:recommendation_event, user: user, album: create(:album, title: "Own Album"), outcome: "pending")
    actioned_event = create(:recommendation_event, user: user, album: create(:album, title: "Actioned Album"), outcome: "good")

    get "/feedback", params: { recommendation_event_id: actioned_event.id }

    expect(response.body).to include("Own Album")
    expect(response.body).not_to include("Actioned Album")
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
