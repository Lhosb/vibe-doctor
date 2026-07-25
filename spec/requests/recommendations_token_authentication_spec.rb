require "rails_helper"

RSpec.describe "POST /recommend with API token authentication", type: :request do
  let(:user) { create(:user) }
  let!(:album) { create(:album, :grounded, genres: [ "Jazz" ], artists: [ "Artist A" ]) }

  let(:intent_schema) do
    QueryUnderstandingClient::Schema.new(
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
      genre: "Jazz", keywords: [ "mellow" ]
    )
  end
  let(:rerank_schema) do
    RerankClient::Schema.new(
      rankings: [ RerankClient::Ranking.new(album_id: album.id, rerank_score: 0.9, rationale: "warm and mellow") ]
    )
  end

  def fake_message_response(parsed)
    content_item = Struct.new(:type, :parsed).new(:output_text, parsed)
    output_item = Struct.new(:type, :content).new(:message, [ content_item ])
    Struct.new(:output).new([ output_item ])
  end

  around do |example|
    original_key = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-key"
    example.run
  ensure
    ENV["OPENAI_API_KEY"] = original_key
  end

  before do
    create(
      :mood_vector, album: album,
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55
    )
    create(
      :embedding, album: album,
      sonic: Array.new(1536, 0.1), emotional: Array.new(1536, 0.1), situational: Array.new(1536, 0.1), era: Array.new(1536, 0.1)
    )

    fake_client = double("OpenAI::Client") # rubocop:disable RSpec/VerifiedDoubles
    responses = double("responses")
    embeddings = double("embeddings")
    allow(OpenAI::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:responses).and_return(responses)
    allow(fake_client).to receive(:embeddings).and_return(embeddings)
    allow(responses).to receive(:create).and_return(fake_message_response(intent_schema), fake_message_response(rerank_schema))
    allow(embeddings).to receive(:create).and_return(Struct.new(:data).new([ Struct.new(:embedding).new(Array.new(1536, 0.1)) ]))
  end

  it "returns the recommendation contract for a valid bearer token, with no cookie session" do
    post "/recommend",
      params: { query: "warm sunday jazz" },
      headers: { "Authorization" => "Bearer #{user.api_token}" },
      as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["explanation"]).to eq("warm and mellow")

    event = RecommendationEvent.find(body["recommendation_event_id"])
    expect(event.user).to eq(user)
  end

  it "returns 401 JSON for an unknown token" do
    post "/recommend",
      params: { query: "warm sunday jazz" },
      headers: { "Authorization" => "Bearer not-a-real-token" },
      as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "returns 401 JSON when no auth is present at all" do
    post "/recommend", params: { query: "warm sunday jazz" }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "no longer authenticates with a token after it has been regenerated" do
    old_token = user.api_token
    user.regenerate_api_token!

    post "/recommend",
      params: { query: "warm sunday jazz" },
      headers: { "Authorization" => "Bearer #{old_token}" },
      as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
