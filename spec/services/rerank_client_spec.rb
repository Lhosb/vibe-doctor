require "rails_helper"

RSpec.describe RerankClient do
  let(:album_a) { create(:album, :grounded, title: "A", artists: ["Artist A"], genres: ["Jazz"]) }
  let(:album_b) { create(:album, :grounded, title: "B", artists: ["Artist B"], genres: ["Jazz"]) }
  let(:ranked_candidates) do
    [
      RankedCandidate::Ranked.new(album: album_a, blended_score: 0.2, affinity: 0.0, cooldown_penalty: 0.0, final_score: 0.8),
      RankedCandidate::Ranked.new(album: album_b, blended_score: 0.3, affinity: 0.0, cooldown_penalty: 0.0, final_score: 0.7)
    ]
  end
  let(:client) { double("OpenAI::Client") } # rubocop:disable RSpec/VerifiedDoubles

  subject(:rerank_client) { described_class.new(client: client) }

  def fake_response(rankings)
    schema = RerankClient::Schema.new(rankings: rankings)
    content_item = Struct.new(:type, :parsed).new(:output_text, schema)
    output_item = Struct.new(:type, :content).new(:message, [content_item])
    Struct.new(:output).new([output_item])
  end

  it "returns candidates reordered and scored by the LLM" do
    rankings = [
      RerankClient::Ranking.new(album_id: album_b.id, rerank_score: 0.95, rationale: "closer match"),
      RerankClient::Ranking.new(album_id: album_a.id, rerank_score: 0.40, rationale: "decent match")
    ]
    allow(client).to receive_message_chain(:responses, :create).and_return(fake_response(rankings))

    result = rerank_client.rerank(query_text: "warm sunday jazz", ranked_candidates: ranked_candidates)

    expect(result.first).to include(album: album_b, rerank_score: 0.95)
    expect(result.last).to include(album: album_a, rerank_score: 0.40)
  end

  it "sends the query text, the schema, and album id/title/artists/genres in the prompt" do
    responses = double("responses")
    allow(client).to receive(:responses).and_return(responses)
    expect(responses).to receive(:create) do |**kwargs|
      expect(kwargs[:text]).to eq(RerankClient::Schema)
      expect(kwargs[:input][1][:content]).to include("warm sunday jazz").and include(album_a.title).and include("Artist A")
      fake_response([])
    end

    rerank_client.rerank(query_text: "warm sunday jazz", ranked_candidates: ranked_candidates)
  end

  it "drops rankings for album ids not present in the ranked candidates" do
    rankings = [RerankClient::Ranking.new(album_id: -1, rerank_score: 0.9, rationale: "unknown")]
    allow(client).to receive_message_chain(:responses, :create).and_return(fake_response(rankings))

    result = rerank_client.rerank(query_text: "x", ranked_candidates: ranked_candidates)

    expect(result).to eq([])
  end

  it "wraps LLM failures in RerankClient::Error" do
    allow(client).to receive(:responses).and_raise(StandardError, "rate limited")

    expect { rerank_client.rerank(query_text: "x", ranked_candidates: ranked_candidates) }
      .to raise_error(RerankClient::Error, /rate limited/)
  end

  it "raises when the response has no parsed rankings" do
    empty_response = Struct.new(:output).new([])
    allow(client).to receive_message_chain(:responses, :create).and_return(empty_response)

    expect { rerank_client.rerank(query_text: "x", ranked_candidates: ranked_candidates) }
      .to raise_error(RerankClient::Error, /no rerank results/)
  end
end
