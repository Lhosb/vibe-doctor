require "rails_helper"

RSpec.describe Recommendations::CandidateRetrieval do
  let(:query_mood) do
    MoodVector.new(
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
      mood_source: "llm_only"
    )
  end
  let(:understanding) do
    instance_double(QueryUnderstandingCache, embedding: Array.new(1536, 0.1), mood_vector: query_mood)
  end

  let!(:close_album) do
    album = create(:album, :grounded)
    create(
      :mood_vector, album: album,
      valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55
    )
    create(
      :embedding, album: album,
      sonic: Array.new(1536, 0.1), emotional: Array.new(1536, 0.1), situational: Array.new(1536, 0.1), era: Array.new(1536, 0.1)
    )
    album
  end

  let!(:far_album) do
    album = create(:album, :grounded)
    create(
      :mood_vector, album: album,
      valence: 0.05, arousal: 0.9, danceability: 0.05, mood_acoustic: 0.05, mood_relaxed: 0.05, mood_happy: 0.05
    )
    create(
      :embedding, album: album,
      sonic: Array.new(1536, 0.9), emotional: Array.new(1536, 0.9), situational: Array.new(1536, 0.9), era: Array.new(1536, 0.9)
    )
    album
  end

  it "ranks albums closer to the query mood and embeddings first" do
    candidates = described_class.new(understanding, limit: 10).call

    expect(candidates.first.album).to eq(close_album)
    expect(candidates.first.blended_score).to be < candidates.last.blended_score
  end

  it "limits the number of candidates returned" do
    candidates = described_class.new(understanding, limit: 1).call

    expect(candidates.length).to eq(1)
  end

  it "only returns candidates within the provided album scope" do
    candidates = described_class.new(understanding, limit: 10, album_ids: [ far_album.id ]).call

    expect(candidates.map { |candidate| candidate.album.id }).to eq([ far_album.id ])
  end

  it "returns no candidates when the provided album scope is empty" do
    candidates = described_class.new(understanding, limit: 10, album_ids: []).call

    expect(candidates).to eq([])
  end

  it "uses mood as the sole discriminator and preserves its exact score gap (G9)" do
    query_row = mood_scale_query_rows.find { |row| row.fetch("id") == "q02" }
    query_mood = mood_vector_from_fixture(query_row, mood_source: "llm_only")
    scoped_understanding = instance_double(
      QueryUnderstandingCache,
      embedding: Array.new(1536, 0.1),
      mood_vector: query_mood
    )
    preferred_album = create_fixture_album(mood_scale_album_rows.fetch(0))
    other_album = create_fixture_album(mood_scale_album_rows.fetch(1))

    candidates = described_class.new(
      scoped_understanding,
      limit: 2,
      album_ids: [ preferred_album.id, other_album.id ]
    ).call

    preferred_term = MoodVectors::MoodDistance.term(album_mood: preferred_album.mood_vector, query_mood:)
    other_term = MoodVectors::MoodDistance.term(album_mood: other_album.mood_vector, query_mood:)
    expected_gap = 0.20 * (other_term - preferred_term)

    expect(candidates.map(&:album)).to eq([ preferred_album, other_album ])
    expect(candidates.last.blended_score - candidates.first.blended_score).to be_within(1e-9).of(expected_gap)
  end

  def create_fixture_album(row)
    album = create(:album, :grounded)
    mood_vector_from_fixture(row, mood_source: "essentia_itunes", album:).save!
    create(
      :embedding,
      album:,
      sonic: Array.new(1536, 0.2),
      emotional: Array.new(1536, 0.2),
      situational: Array.new(1536, 0.2),
      era: Array.new(1536, 0.2)
    )

    album
  end
end
