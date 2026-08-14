require "rails_helper"

RSpec.describe MoodVectors::CatalogueScale do
  it "exposes a frozen, versioned catalog-scale table" do
    expect(described_class::VERSION).to be_a(String)
    expect(described_class::SAMPLE_SIZE).to eq(321)

    expect(described_class::HEADS).to contain_exactly(
      :valence,
      :arousal,
      :danceability,
      :mood_acoustic,
      :mood_happy,
      :mood_relaxed
    )

    expect(described_class::MU.keys).to contain_exactly(*described_class::HEADS)
    expect(described_class::SIGMA.keys).to contain_exactly(*described_class::HEADS)

    expect(described_class::MU).to be_frozen
    expect(described_class::SIGMA).to be_frozen
    expect(described_class::HEADS).to be_frozen
    expect(described_class::FINDING_B_CORRELATION).to be_frozen
  end

  it "declares finding B correlation explicitly" do
    expect(described_class::FINDING_B_CORRELATION.fetch(:arousal_vs_mood_relaxed)).to eq(-0.9014)
  end

  it "pins reference distance to standardized z-space (not stored 0..1 space)" do
    expect(described_class::REFERENCE_DISTANCE).to eq(3.021725)
  end

  it "raises when drift recomputation has no grounded rows" do
    expect do
      described_class.recompute_statistics(scope: MoodVector.none)
    end.to raise_error(ArgumentError, /grounded mood rows/)
  end

  it "recomputes sigma over grounded rows and reports nonzero row_count" do
    album_a = create(:album, master_id: 10_001)
    album_b = create(:album, master_id: 10_002)
    album_c = create(:album, master_id: 10_003)

    create(
      :mood_vector,
      album: album_a,
      mood_source: "essentia_itunes",
      valence: 0.40,
      arousal: 0.41,
      danceability: 0.42,
      mood_acoustic: 0.43,
      mood_happy: 0.44,
      mood_relaxed: 0.45
    )
    create(
      :mood_vector,
      album: album_b,
      mood_source: "essentia_youtube",
      valence: 0.50,
      arousal: 0.51,
      danceability: 0.52,
      mood_acoustic: 0.53,
      mood_happy: 0.54,
      mood_relaxed: 0.55
    )
    create(
      :mood_vector,
      album: album_c,
      mood_source: "essentia_itunes",
      valence: 0.60,
      arousal: 0.61,
      danceability: 0.62,
      mood_acoustic: 0.63,
      mood_happy: 0.64,
      mood_relaxed: 0.65
    )

    result = described_class.recompute_statistics(scope: MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube]))

    expect(result.fetch(:row_count)).to eq(3)
    expect(result.fetch(:sigma).keys).to contain_exactly(*described_class::HEADS)
    expect(result.fetch(:sigma).fetch(:valence)).to be > 0
    expect(result.fetch(:sigma).fetch(:mood_relaxed)).to be > 0
  end

  it "fails when injected drift exceeds tolerance and passes just inside the band" do
    album_a = create(:album, master_id: 20_001)
    album_b = create(:album, master_id: 20_002)
    album_c = create(:album, master_id: 20_003)

    create(
      :mood_vector,
      album: album_a,
      mood_source: "essentia_itunes",
      valence: 0.40,
      arousal: 0.41,
      danceability: 0.42,
      mood_acoustic: 0.43,
      mood_happy: 0.44,
      mood_relaxed: 0.45
    )
    create(
      :mood_vector,
      album: album_b,
      mood_source: "essentia_youtube",
      valence: 0.50,
      arousal: 0.51,
      danceability: 0.52,
      mood_acoustic: 0.53,
      mood_happy: 0.54,
      mood_relaxed: 0.55
    )
    create(
      :mood_vector,
      album: album_c,
      mood_source: "essentia_itunes",
      valence: 0.60,
      arousal: 0.61,
      danceability: 0.62,
      mood_acoustic: 0.63,
      mood_happy: 0.64,
      mood_relaxed: 0.65
    )

    scope = MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube])
    observed_sigma = described_class.recompute_statistics(scope:).fetch(:sigma)

    outside_band_baseline = observed_sigma.merge(arousal: observed_sigma.fetch(:arousal) / 1.251)
    inside_band_baseline = observed_sigma.merge(arousal: observed_sigma.fetch(:arousal) / 1.249)

    outside_report = described_class.drift_report(scope:, baseline_sigma: outside_band_baseline)
    inside_report = described_class.drift_report(scope:, baseline_sigma: inside_band_baseline)

    expect(outside_report.fetch(:row_count)).to eq(3)
    expect(outside_report.fetch(:within_tolerance)).to be(false)
    expect(outside_report.fetch(:breaches)).to include(:arousal)

    expect(inside_report.fetch(:row_count)).to eq(3)
    expect(inside_report.fetch(:within_tolerance)).to be(true)
    expect(inside_report.fetch(:breaches)).to be_empty
  end
end
