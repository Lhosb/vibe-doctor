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
