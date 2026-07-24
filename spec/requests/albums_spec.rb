require "rails_helper"

RSpec.describe "GET /albums/:id", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "shows year, genres, and styles in the header" do
    album = create(:album, :grounded, title: "Kind of Blue", year: 1959, genres: [ "Jazz" ], styles: [ "Modal" ])

    get album_path(album)

    expect(response.body).to include("1959")
    expect(response.body).to include("Jazz")
    expect(response.body).to include("Modal")
  end
end
