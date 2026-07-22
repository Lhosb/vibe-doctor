require "rails_helper"

RSpec.describe "Discogs connection", type: :system do
  let(:user) { create(:user, email_address: "listener@example.com", password: "s3cret-pass") }

  before do
    allow(EnrichAlbumJob).to receive(:perform_later)

    stub_request(:get, "https://api.discogs.com/users/listener/collection/folders/0/releases")
      .with(query: { page: "1", per_page: "100" })
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          pagination: { page: 1, pages: 1, per_page: 100, items: 1 },
          releases: [
            {
              id: 111,
              instance_id: 9001,
              basic_information: {
                id: 111,
                master_id: 500,
                title: "Album One",
                year: 1999,
                genres: ["Rock"],
                styles: ["Alternative Rock"],
                artists: [{ name: "Band One" }]
              }
            }
          ]
        }.to_json
      )
  end

  it "logs in, connects a Discogs account, and populates the library" do
    visit new_session_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: "s3cret-pass"
    click_button "Sign in"

    click_link "Connect Discogs"
    fill_in "Discogs username", with: "listener"
    fill_in "Discogs personal access token", with: "test-token-abc"

    perform_enqueued_jobs do
      click_button "Connect"
    end

    expect(page).to have_content("Album One")
    expect(CollectionItem.where(user: user).count).to eq(1)
  end
end
