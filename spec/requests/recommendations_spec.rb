require "rails_helper"

RSpec.describe "POST /recommend", type: :request do
  let(:user) { create(:user, password: "s3cret-pass") }
  let!(:album) { create(:album, :grounded, genres: ["Jazz"], artists: ["Artist A"]) }

  let(:intent_schema) do
    QueryUnderstandingClient::Schema.new(
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
      genre: "Jazz", keywords: ["mellow"]
    )
  end
  let(:rerank_schema) do
    RerankClient::Schema.new(
      rankings: [RerankClient::Ranking.new(album_id: album.id, rerank_score: 0.9, rationale: "warm and mellow")]
    )
  end

  def fake_message_response(parsed)
    content_item = Struct.new(:type, :parsed).new(:output_text, parsed)
    output_item = Struct.new(:type, :content).new(:message, [content_item])
    Struct.new(:output).new([output_item])
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
    allow(embeddings).to receive(:create).and_return(Struct.new(:data).new([Struct.new(:embedding).new(Array.new(1536, 0.1))]))

    post session_path, params: { email_address: user.email_address, password: "s3cret-pass" }
  end

  it "returns the recommendation contract" do
    post "/recommend", params: { query: "warm sunday jazz" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to contain_exactly("recommendation_event_id", "album", "explanation")
    expect(body["recommendation_event_id"]).to be_a(Integer)
    expect(body["album"].keys).to contain_exactly("id", "title", "artists", "genres")
    expect(body["explanation"]).to eq("warm and mellow")
  end

  it "returns 422 when no albums are admitted" do
    album.destroy!

    post "/recommend", params: { query: "warm sunday jazz" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to be_present
  end

  it "returns 400 when query is missing" do
    post "/recommend", params: {}

    expect(response).to have_http_status(:bad_request)
  end

  it "requires authentication" do
    delete session_path

    post "/recommend", params: { query: "warm sunday jazz" }

    expect(response).to have_http_status(:redirect)
  end
end
