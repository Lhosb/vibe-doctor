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

  it "records normalized shares for exactly the six named mood heads (G17)", :aggregate_failures do
    retrieval = fixture_retrieval(query: query_mood)
    expected_shares = expected_fixture_shares(query_mood)

    retrieval.call
    instrumentation = retrieval.head_shares
    shares = instrumentation.fetch("shares")

    expect(instrumentation.fetch("scored_count")).to eq(321)
    expect(instrumentation.fetch("total_weighted_sq_distance")).to be > 0.0
    expect(shares.keys.to_set).to eq(MoodVector::MOOD_HEADS.map(&:to_s).to_set)
    expect(shares.values).to all(be_between(0.0, 1.0))
    expect(shares.values.sum).to be_within(1e-12).of(1.0)
    MoodVector::MOOD_HEADS.each do |head|
      expect(shares.fetch(head.to_s)).to be_within(1e-12).of(expected_shares.fetch(head.to_s))
    end
  end

  it "relates recorded shares to variance shares only at the calibrated fixture mean (G18)", :aggregate_failures do
    calibrated_coordinates = MoodVector::MOOD_HEADS.to_h do |head|
      values = mood_scale_album_rows.map do |row|
        mood = mood_vector_from_fixture(row, mood_source: "essentia_itunes")
        MoodVectors::HeadCalibration.album_coordinate(mood, head)
      end
      [ head, values ]
    end
    mean_query = MoodVector.new(
      **calibrated_coordinates.transform_values { |values| values.sum / values.size },
      mood_source: "llm_only"
    )
    variance_shares = normalized_head_values do |head|
      population_variance(calibrated_coordinates.fetch(head)) * MoodVectors::HeadWeights.for(head)
    end
    mean_retrieval = fixture_retrieval(query: mean_query)
    off_center_retrieval = fixture_retrieval(query: query_mood)

    mean_retrieval.call
    off_center_retrieval.call
    mean_query_shares = mean_retrieval.head_shares.fetch("shares")
    off_center_shares = off_center_retrieval.head_shares.fetch("shares")

    expect(variance_shares.size).to eq(6)
    expect(mean_query_shares.size).to eq(6)
    expect(off_center_shares.size).to eq(6)
    MoodVector::MOOD_HEADS.each do |head|
      expect(mean_query_shares.fetch(head.to_s)).to be_within(1e-9).of(variance_shares.fetch(head.to_s))
    end
    expect(
      MoodVector::MOOD_HEADS.sum do |head|
        (off_center_shares.fetch(head.to_s) - variance_shares.fetch(head.to_s)).abs
      end
    ).to be > 0.01
  end

  it "records every scored candidate before the result limit (G19)" do
    limit = 1
    mood_scale_album_rows.first(4).each { |row| create_fixture_album(row) }
    retrieval = described_class.new(understanding, limit:)
    candidate_ids = retrieval.send(:facet_distance_maps).values.flat_map(&:keys).uniq

    expect(candidate_ids.size).to be >= limit + 4

    retrieval.call

    expect(retrieval.head_shares.fetch("scored_count")).to eq(candidate_ids.size)
  end

  it "records the maximum observed term within the published no-clamp bound (G21)", :aggregate_failures do
    retrieval = fixture_retrieval(query: query_mood)
    expected_terms = mood_scale_album_rows.map do |row|
      MoodVectors::MoodDistance.term(
        album_mood: mood_vector_from_fixture(row, mood_source: "essentia_itunes"),
        query_mood:
      )
    end

    expect(expected_terms.size).to be > 1

    retrieval.call

    expect(retrieval.head_shares.fetch("max_term")).to eq(expected_terms.max)
    expect(retrieval.head_shares.fetch("max_term")).to be <= MoodScaleFixture::G15_MAX_TERM
  end

  it "records the conditional share invariant for a scored candidate at zero mood distance (G23)", :aggregate_failures do
    centered_mood = MoodVector.new(
      **MoodVector::MOOD_HEADS.to_h { |head| [ head, 0.5 ] },
      mood_source: "llm_only"
    )
    retrieval = fixture_retrieval(
      query: centered_mood,
      album_rows: [ MoodVector::MOOD_HEADS.to_h { |head| [ head.to_s, 0.5 ] } ]
    )
    breakdown = MoodVectors::MoodDistance.breakdown(
      album_mood: mood_vector_from_fixture(
        MoodVector::MOOD_HEADS.to_h { |head| [ head.to_s, 0.5 ] },
        mood_source: "essentia_itunes"
      ),
      query_mood: centered_mood
    )

    expect(breakdown.per_head.values.sum).to eq(0.0)

    expect { retrieval.call }.not_to raise_error
    instrumentation = retrieval.head_shares
    shares = instrumentation.fetch("shares")

    expect(instrumentation.fetch("total_weighted_sq_distance")).to eq(0.0)
    expect(instrumentation.fetch("total_weighted_sq_distance").zero? || shares.values.sum == 1.0).to be(true)
    expect(instrumentation).to eq(
      "shares" => MoodVector::MOOD_HEADS.to_h { |head| [ head.to_s, 0.0 ] },
      "max_term" => 0.0,
      "scored_count" => 1,
      "total_weighted_sq_distance" => 0.0
    )
  end

  it "applies distinct head weights to specifically predicted recorded shares (G24)", :aggregate_failures do
    album_row = {
      "valence" => 0.75,
      "arousal" => 0.75,
      "danceability" => 1.0,
      "mood_acoustic" => 1.0,
      "mood_relaxed" => 1.0,
      "mood_happy" => 1.0
    }
    zero_query = MoodVector.new(
      **MoodVector::MOOD_HEADS.to_h { |head| [ head, 0.0 ] },
      mood_source: "llm_only"
    )
    uniform_retrieval = fixture_retrieval(query: zero_query, album_rows: [ album_row ])
    uniform_retrieval.call
    uniform_shares = uniform_retrieval.head_shares.fetch("shares")
    distinct_weights = {
      valence: 1.0,
      arousal: 2.0,
      danceability: 3.0,
      mood_acoustic: 4.0,
      mood_relaxed: 5.0,
      mood_happy: 6.0
    }.freeze
    expected_shares = {
      "valence" => 1.0 / 21.0,
      "arousal" => 2.0 / 21.0,
      "danceability" => 3.0 / 21.0,
      "mood_acoustic" => 4.0 / 21.0,
      "mood_relaxed" => 5.0 / 21.0,
      "mood_happy" => 6.0 / 21.0
    }

    expect(distinct_weights.values.uniq.size).to eq(6)

    stub_const("MoodVectors::HeadWeights::WEIGHTS", distinct_weights)
    weighted_retrieval = fixture_retrieval(query: zero_query, album_rows: [ album_row ])
    weighted_retrieval.call
    instrumentation = weighted_retrieval.head_shares
    weighted_shares = instrumentation.fetch("shares")

    expect(
      MoodVector::MOOD_HEADS.count do |head|
        weighted_shares.fetch(head.to_s) != uniform_shares.fetch(head.to_s)
      end
    ).to be >= 2
    expect(instrumentation.fetch("total_weighted_sq_distance")).to eq(21.0)
    expected_shares.each do |head, expected_share|
      expect(weighted_shares.fetch(head)).to be_within(1e-12).of(expected_share)
    end
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

  def fixture_retrieval(query:, album_rows: mood_scale_album_rows)
    albums = album_rows.each_with_index.map do |row, index|
      Struct.new(:id, :mood_vector).new(
        index + 1,
        mood_vector_from_fixture(row, mood_source: "essentia_itunes")
      )
    end
    album_ids = albums.map(&:id)
    maps = described_class::FACET_WEIGHTS.each_key.to_h do |facet|
      [ facet, album_ids.to_h { |album_id| [ album_id, 0.0 ] } ]
    end
    relation = double(includes: albums)
    fixture_understanding = instance_double(
      QueryUnderstandingCache,
      embedding: Array.new(1536, 0.1),
      mood_vector: query
    )
    retrieval = described_class.new(fixture_understanding, limit: albums.size)

    allow(retrieval).to receive(:facet_distance_maps).and_return(maps)
    allow(Album).to receive(:where).with(id: album_ids).and_return(relation)

    retrieval
  end

  def expected_fixture_shares(query)
    normalized_head_values do |head|
      mood_scale_album_rows.sum do |row|
        album_mood = mood_vector_from_fixture(row, mood_source: "essentia_itunes")
        MoodVectors::MoodDistance.breakdown(album_mood:, query_mood: query).per_head.fetch(head)
      end
    end
  end

  def normalized_head_values
    values = MoodVector::MOOD_HEADS.to_h { |head| [ head.to_s, yield(head) ] }
    total = values.values.sum

    values.transform_values { |value| value / total }
  end

  def population_variance(values)
    mean = values.sum / values.size

    values.sum { |value| (value - mean)**2 } / values.size
  end
end
