require "rails_helper"

RSpec.describe "GET /recommend", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "renders the recommend form" do
    get "/recommend"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-recommend-target="query"))
    expect(response.body).to include(%(data-recommend-target="genre"))
    expect(response.body).to include(%(data-recommend-target="result"))
  end

  it "requires authentication" do
    delete session_path

    get "/recommend"

    expect(response).to have_http_status(:redirect)
  end
end
