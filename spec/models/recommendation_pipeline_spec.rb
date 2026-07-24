require "rails_helper"

RSpec.describe RecommendationPipeline do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, artists: [ "Artist A" ], genres: [ "Jazz" ]) }

  before do
    allow(QueryUnderstandingCache).to receive(:fetch).and_return(
      instance_double(
        QueryUnderstandingCache,
        embedding: Array.new(1536, 0.1),
        mood_vector: MoodVector.new(
          valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
          mood_source: "llm_only"
        ),
        genre: "Jazz"
      )
    )
    allow(CandidateRetrieval).to receive(:new).and_return(
      instance_double(CandidateRetrieval, call: [ CandidateRetrieval::Candidate.new(album: album, blended_score: 0.2) ])
    )
    allow(RerankClient).to receive(:new).and_return(
      instance_double(RerankClient, rerank: [ { album: album, rerank_score: 0.9, rationale: "warm and mellow" } ])
    )
  end

  it "returns the chosen album, persists a linked event with the pipeline's scores, and records artist cooldown" do
    result = described_class.new(user: user, query_text: "warm sunday jazz").call

    expect(result.album).to eq(album)
    expect(result.explanation).to eq("warm and mellow")
    expect(result.recommendation_event).to be_persisted

    event = result.recommendation_event
    expect(event.album).to eq(album)
    expect(event.user).to eq(user)
    expect(event).to have_attributes(
      query_text: "warm sunday jazz",
      candidates_considered: 1,
      explanation: "warm and mellow"
    )
    expect(event.blended_scores).to eq(album.id.to_s => 0.2)
    expect(event.rerank_scores).to eq(album.id.to_s => 0.9)
    expect(event.final_score).to be_within(0.0001).of(1.0 / 1.2)

    expect(ArtistCooldown.penalty_for(user: user, artist_name: "Artist A")).to be > 0.0
  end

  it "records cooldown for every credited artist on a multi-artist album" do
    collab_album = create(:album, :grounded, artists: [ "Artist A", "Artist B" ])
    allow(CandidateRetrieval).to receive(:new).and_return(
      instance_double(CandidateRetrieval, call: [ CandidateRetrieval::Candidate.new(album: collab_album, blended_score: 0.2) ])
    )
    allow(RerankClient).to receive(:new).and_return(
      instance_double(RerankClient, rerank: [ { album: collab_album, rerank_score: 0.9, rationale: "warm and mellow" } ])
    )

    described_class.new(user: user, query_text: "warm sunday jazz").call

    expect(ArtistCooldown.penalty_for(user: user, artist_name: "Artist A")).to be > 0.0
    expect(ArtistCooldown.penalty_for(user: user, artist_name: "Artist B")).to be > 0.0
  end

  it "raises NoCandidatesError when admission yields nothing" do
    allow(CandidateRetrieval).to receive(:new).and_return(instance_double(CandidateRetrieval, call: []))

    expect { described_class.new(user: user, query_text: "warm sunday jazz").call }
      .to raise_error(RecommendationPipeline::NoCandidatesError)
  end
end
