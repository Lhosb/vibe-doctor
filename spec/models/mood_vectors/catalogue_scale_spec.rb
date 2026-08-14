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
    expect(described_class::FINDING_B_CORRELATION.fetch(:valence_vs_arousal)).to eq(0.7146)
  end

  it "pins reference distance to standardized z-space (not stored 0..1 space)" do
    expect(described_class::REFERENCE_DISTANCE).to eq(3.0217250259)
  end

  it "pins frozen mu and sigma constants to the approved frozen values" do
    expected_mu = {
      valence: 0.5113469703,
      arousal: 0.4924708821,
      danceability: 0.5288407371,
      mood_acoustic: 0.4234423973,
      mood_happy: 0.5453354621,
      mood_relaxed: 0.5285604759
    }
    expected_sigma = {
      valence: 0.0592340732,
      arousal: 0.0870053745,
      danceability: 0.3348149979,
      mood_acoustic: 0.3208211343,
      mood_happy: 0.2689669437,
      mood_relaxed: 0.3136104494
    }

    expect(described_class::MU).to eq(expected_mu)
    expect(described_class::SIGMA).to eq(expected_sigma)
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
    expected_sigma = Math.sqrt(0.02 / 3.0)
    expected_mu = {
      valence: 0.5,
      arousal: 0.51,
      danceability: 0.52,
      mood_acoustic: 0.53,
      mood_happy: 0.54,
      mood_relaxed: 0.55
    }

    described_class::HEADS.each do |head|
      expect(result.fetch(:mu).fetch(head)).to be_within(1e-12).of(expected_mu.fetch(head))
      expect(result.fetch(:sigma).fetch(head)).to be_within(1e-12).of(expected_sigma)
    end
  end

  it "fails and passes around the shrink-side breach boundary" do
    album_a = create(:album, master_id: 20_001)
    album_b = create(:album, master_id: 20_002)
    album_c = create(:album, master_id: 20_003)

    create(
      :mood_vector,
      album: album_a,
      mood_source: "essentia_itunes",
      valence: 0.40,
      arousal: 0.41,
      danceability: 0.20,
      mood_acoustic: 0.10,
      mood_happy: 0.30,
      mood_relaxed: 0.90
    )
    create(
      :mood_vector,
      album: album_b,
      mood_source: "essentia_youtube",
      valence: 0.50,
      arousal: 0.51,
      danceability: 0.50,
      mood_acoustic: 0.40,
      mood_happy: 0.60,
      mood_relaxed: 0.30
    )
    create(
      :mood_vector,
      album: album_c,
      mood_source: "essentia_itunes",
      valence: 0.60,
      arousal: 0.61,
      danceability: 0.80,
      mood_acoustic: 0.70,
      mood_happy: 0.90,
      mood_relaxed: 0.10
    )

    scope = MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube])
    observed_sigma = described_class.recompute_statistics(scope:).fetch(:sigma)

    outside_band_baseline = observed_sigma.merge(danceability: observed_sigma.fetch(:danceability) * 1.3334)
    inside_band_baseline = observed_sigma.merge(danceability: observed_sigma.fetch(:danceability) * 1.3333)

    outside_report = described_class.drift_report(scope:, baseline_sigma: outside_band_baseline)
    inside_report = described_class.drift_report(scope:, baseline_sigma: inside_band_baseline)

    expect(outside_report.fetch(:row_count)).to eq(3)
    expect(outside_report.fetch(:within_tolerance)).to be(false)
    expect(outside_report.fetch(:breaches)).to include(:danceability)

    expect(inside_report.fetch(:row_count)).to eq(3)
    expect(inside_report.fetch(:within_tolerance)).to be(true)
    expect(inside_report.fetch(:breaches)).to be_empty
  end

  it "fails and passes around the growth-side breach boundary" do
    album_a = create(:album, master_id: 21_001)
    album_b = create(:album, master_id: 21_002)
    album_c = create(:album, master_id: 21_003)

    create(
      :mood_vector,
      album: album_a,
      mood_source: "essentia_itunes",
      valence: 0.20,
      arousal: 0.40,
      danceability: 0.10,
      mood_acoustic: 0.25,
      mood_happy: 0.35,
      mood_relaxed: 0.70
    )
    create(
      :mood_vector,
      album: album_b,
      mood_source: "essentia_youtube",
      valence: 0.50,
      arousal: 0.60,
      danceability: 0.50,
      mood_acoustic: 0.55,
      mood_happy: 0.65,
      mood_relaxed: 0.40
    )
    create(
      :mood_vector,
      album: album_c,
      mood_source: "essentia_itunes",
      valence: 0.80,
      arousal: 0.80,
      danceability: 0.90,
      mood_acoustic: 0.85,
      mood_happy: 0.95,
      mood_relaxed: 0.10
    )

    scope = MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube])
    observed_sigma = described_class.recompute_statistics(scope:).fetch(:sigma)

    outside_band_baseline = observed_sigma.merge(mood_happy: observed_sigma.fetch(:mood_happy) / 1.251)
    inside_band_baseline = observed_sigma.merge(mood_happy: observed_sigma.fetch(:mood_happy) / 1.249)

    outside_report = described_class.drift_report(scope:, baseline_sigma: outside_band_baseline)
    inside_report = described_class.drift_report(scope:, baseline_sigma: inside_band_baseline)

    expect(outside_report.fetch(:row_count)).to eq(3)
    expect(outside_report.fetch(:within_tolerance)).to be(false)
    expect(outside_report.fetch(:breaches)).to include(:mood_happy)

    expect(inside_report.fetch(:row_count)).to eq(3)
    expect(inside_report.fetch(:within_tolerance)).to be(true)
    expect(inside_report.fetch(:breaches)).to be_empty
  end

  it "re-derives deterministic fixture distance from published SIGMA constants" do
    rows = [
      [ 0.40, 0.41, 0.20, 0.10, 0.30, 0.90 ],
      [ 0.50, 0.51, 0.50, 0.40, 0.60, 0.30 ],
      [ 0.60, 0.61, 0.80, 0.70, 0.90, 0.10 ]
    ]
    columns = described_class::HEADS
    distances = []
    rows.each_with_index do |left, left_index|
      ((left_index + 1)...rows.length).each do |right_index|
        right = rows.fetch(right_index)
        squared = columns.each_with_index.sum do |head, index|
          ((left.fetch(index) - right.fetch(index)) / described_class::SIGMA.fetch(head))**2
        end
        distances << Math.sqrt(squared)
      end
    end
    expected_reference = distances.sort.fetch(1)

    album_a = create(:album, master_id: 30_001)
    album_b = create(:album, master_id: 30_002)
    album_c = create(:album, master_id: 30_003)

    create(:mood_vector, album: album_a, mood_source: "essentia_itunes", valence: rows[0][0], arousal: rows[0][1], danceability: rows[0][2], mood_acoustic: rows[0][3], mood_happy: rows[0][4], mood_relaxed: rows[0][5])
    create(:mood_vector, album: album_b, mood_source: "essentia_youtube", valence: rows[1][0], arousal: rows[1][1], danceability: rows[1][2], mood_acoustic: rows[1][3], mood_happy: rows[1][4], mood_relaxed: rows[1][5])
    create(:mood_vector, album: album_c, mood_source: "essentia_itunes", valence: rows[2][0], arousal: rows[2][1], danceability: rows[2][2], mood_acoustic: rows[2][3], mood_happy: rows[2][4], mood_relaxed: rows[2][5])

    report = described_class.reference_distance_report(scope: MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube]))
    expect(report.fetch(:row_count)).to eq(3)
    expect(report.fetch(:pair_count)).to eq(3)
    expect(report.fetch(:reference_distance_from_constants)).to be_within(1e-12).of(expected_reference)
  end

  it "exercises the even-pair median branch for reference distance" do
    rows = [
      [ 0.10, 0.30, 0.20, 0.10, 0.20, 0.90 ],
      [ 0.20, 0.40, 0.30, 0.20, 0.30, 0.80 ],
      [ 0.70, 0.60, 0.80, 0.70, 0.90, 0.10 ],
      [ 0.80, 0.70, 0.90, 0.80, 0.95, 0.05 ]
    ]

    albums = 4.times.map { |index| create(:album, master_id: 31_001 + index) }
    rows.each_with_index do |values, index|
      create(
        :mood_vector,
        album: albums.fetch(index),
        mood_source: index.even? ? "essentia_itunes" : "essentia_youtube",
        valence: values[0],
        arousal: values[1],
        danceability: values[2],
        mood_acoustic: values[3],
        mood_happy: values[4],
        mood_relaxed: values[5]
      )
    end

    report = described_class.reference_distance_report(scope: MoodVector.where(mood_source: %w[essentia_itunes essentia_youtube]))
    expect(report.fetch(:row_count)).to eq(4)
    expect(report.fetch(:pair_count)).to eq(6)
    expect(report.fetch(:reference_distance_from_constants)).to be_within(1e-12).of(10.53480373018995)
  end
end
