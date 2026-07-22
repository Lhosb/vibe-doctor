require "rails_helper"

RSpec.describe "Feedback card-stack flow", type: :system, js: true do
  let(:user) { create(:user) }
  let!(:event) { create(:recommendation_event, user: user, outcome: "pending") }

  before { sign_in_as(user) }

  it "advances to the next card after choosing Good" do
    visit "/feedback"
    expect(page).to have_content(event.album.title)

    click_button "Good"

    expect(page).to have_content("You're all caught up!")
    expect(event.reload.outcome).to eq("good")
  end
end
