require "rails_helper"

RSpec.describe "Recommend page", type: :system, js: true do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, title: "Kind of Blue", artists: [ "Miles Davis" ], genres: [ "Jazz" ]) }

  before { sign_in_as(user) }

  it "recommends an album and links to giving feedback on it" do
    event = create(:recommendation_event, user: user, album: album, explanation: "warm and mellow", outcome: "pending")
    result = RecommendationPipeline::Result.new(album: album, explanation: "warm and mellow", recommendation_event: event)
    pipeline = instance_double(RecommendationPipeline, call: result)
    allow(RecommendationPipeline).to receive(:new)
      .with(user: user, query_text: "warm sunday jazz", genre: nil)
      .and_return(pipeline)

    visit "/recommend"
    fill_in "What are you in the mood for?", with: "warm sunday jazz"
    click_button "Get a recommendation"

    expect(page).to have_content("Kind of Blue")
    expect(page).to have_content("Miles Davis")
    expect(page).to have_content("warm and mellow")

    click_link "Give feedback"

    expect(page).to have_current_path(%r{\A/feedback})
    expect(page).to have_content("Kind of Blue")
  end
end
