require "rails_helper"

RSpec.describe QueryUnderstandingClient do
  let(:parsed_intent) do
    QueryUnderstandingClient::Schema.new(
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
      genre: "Jazz", keywords: [ "mellow", "sunday" ]
    )
  end
  let(:fake_content_item) { Struct.new(:type, :parsed).new(:output_text, parsed_intent) }
  let(:fake_output_item) { Struct.new(:type, :content).new(:message, [ fake_content_item ]) }
  let(:fake_response) { Struct.new(:output).new([ fake_output_item ]) }
  let(:client) { double("OpenAI::Client") } # rubocop:disable RSpec/VerifiedDoubles
  let(:embeddings) { double("embeddings") }

  subject(:query_understanding_client) { described_class.new(client: client) }

  def fake_embedding_data
    Struct.new(:data).new([ Struct.new(:embedding).new(Array.new(1536, 0.1)) ])
  end

  before do
    allow(client).to receive_message_chain(:responses, :create).and_return(fake_response)
    allow(client).to receive(:embeddings).and_return(embeddings)
    allow(embeddings).to receive(:create).and_return(fake_embedding_data)
  end

  it "returns a structured understanding of the query" do
    result = query_understanding_client.understand("warm sunday jazz")

    expect(result.mood_vector).to have_attributes(
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
      mood_source: "llm_only"
    )
    expect(result.genre).to eq("Jazz")
    expect(result.keywords).to eq([ "mellow", "sunday" ])
    expect(result.embedding).to eq(Array.new(1536, 0.1))
  end

  it "sends the query text to both the intent schema call and the embedding call" do
    responses = double("responses")
    allow(client).to receive(:responses).and_return(responses)
    expect(responses).to receive(:create) do |**kwargs|
      expect(kwargs[:text]).to eq(QueryUnderstandingClient::Schema)
      expect(kwargs[:input][1][:content]).to eq("warm sunday jazz")
      fake_response
    end
    expect(embeddings).to receive(:create).with(model: "text-embedding-3-small", input: [ "warm sunday jazz" ]).and_return(fake_embedding_data)

    query_understanding_client.understand("warm sunday jazz")
  end

  it "wraps intent-extraction failures in QueryUnderstandingClient::Error" do
    allow(client).to receive(:responses).and_raise(StandardError, "timeout")

    expect { query_understanding_client.understand("warm sunday jazz") }
      .to raise_error(QueryUnderstandingClient::Error, /timeout/)
  end

  it "raises when the response has no parsed message content" do
    empty_response = Struct.new(:output).new([])
    allow(client).to receive_message_chain(:responses, :create).and_return(empty_response)

    expect { query_understanding_client.understand("warm sunday jazz") }
      .to raise_error(QueryUnderstandingClient::Error, /no intent returned/)
  end

  it "wraps embedding failures in QueryUnderstandingClient::Error" do
    allow(embeddings).to receive(:create).and_raise(StandardError, "rate limited")

    expect { query_understanding_client.understand("warm sunday jazz") }
      .to raise_error(QueryUnderstandingClient::Error, /rate limited/)
  end
end
