require "rails_helper"

RSpec.describe "MoodVectors::MoodDistance" do
  OLD_MOOD_VECTOR_WEIGHT = 0.20
  MEAN_DISPERSION_RATIO_RANGE = (0.95..1.06)
  MAX_PER_QUERY_DISPERSION_RATIO = 1.12

  let(:album_vectors) do
    mood_scale_album_rows.map { |row| mood_vector_from_fixture(row, mood_source: "essentia_itunes") }
  end
  let(:query_vectors) do
    mood_scale_query_rows.map { |row| mood_vector_from_fixture(row, mood_source: "llm_only") }
  end

  it "keeps per-head variance influence below the imbalance ceiling with explicit controls (G6)", :aggregate_failures do
    option_e_imbalance = imbalance_ratio(album_vectors) do |mood, head|
      MoodVectors::HeadCalibration.album_coordinate(mood, head)
    end
    declared_band_imbalance = imbalance_ratio(album_vectors) { |mood, head| mood.public_send(head) }

    expect(option_e_imbalance).to be <= 12.0
    expect(option_e_imbalance).to be_within(0.01).of(7.99)
    expect(declared_band_imbalance).to be > 12.0
    expect(declared_band_imbalance).to be_within(0.01).of(31.95)
  end

  it "preserves mean and worst-query mood dispersion (G7)", :aggregate_failures do
    old_sds = query_vectors.map { |query| population_standard_deviation(old_terms(query)) }
    new_sds = query_vectors.map { |query| population_standard_deviation(new_terms(query)) }

    expect(album_vectors.size).to eq(321)
    expect(query_vectors.size).to eq(12)
    expect(old_sds.count(&:positive?)).to eq(12)
    expect(new_sds.count(&:positive?)).to eq(12)
    expect((old_sds.sum / old_sds.size).round(9)).to eq(0.095101457)

    weighted_ratios = new_sds.each_index.map do |index|
      (Recommendations::CandidateRetrieval::MOOD_VECTOR_WEIGHT * new_sds.fetch(index)) /
        (OLD_MOOD_VECTOR_WEIGHT * old_sds.fetch(index))
    end
    mean_ratio = (Recommendations::CandidateRetrieval::MOOD_VECTOR_WEIGHT * new_sds.sum) /
      (OLD_MOOD_VECTOR_WEIGHT * old_sds.sum)
    max_ratio = weighted_ratios.max

    expect(mean_ratio.round(9)).to eq(1.039798885)
    expect(mean_ratio).to be_between(MEAN_DISPERSION_RATIO_RANGE.begin, MEAN_DISPERSION_RATIO_RANGE.end)
    expect(max_ratio.round(9)).to eq(1.114364125)
    expect(max_ratio).to be <= MAX_PER_QUERY_DISPERSION_RATIO
  end

  it "makes high-arousal query coordinates reachable from the album fixture (G8)" do
    calibrated_max = album_vectors.map do |mood|
      MoodVectors::HeadCalibration.album_coordinate(mood, :arousal)
    end.max

    expect(calibrated_max).to be >= 0.85
  end

  it "uses album-side calibration in the shipped metric (G14)", :aggregate_failures do
    album = album_vectors.first
    query_row = mood_scale_query_rows.find { |row| row.fetch("id") == "q02" }
    query = mood_vector_from_fixture(query_row, mood_source: "llm_only")
    actual = described_metric_term(album:, query:)
    calibrated = explicit_term(album:, query:, calibrate_album: true)
    uncalibrated = explicit_term(album:, query:, calibrate_album: false)

    expect(actual).to be_within(1e-12).of(calibrated)
    expect(actual).not_to be_within(1e-6).of(uncalibrated)
  end

  it "pins the deliberate no-clamp nominal-bound overrun (G15)", :aggregate_failures do
    album = mood_vector_with_all_heads(1.0, mood_source: "essentia_itunes")
    query = mood_vector_with_all_heads(0.0, mood_source: "llm_only")
    term = described_metric_term(album:, query:)

    expect(term.round(10)).to eq(1.1902380714)
    expect((Recommendations::CandidateRetrieval::MOOD_VECTOR_WEIGHT * term).round(6)).to eq(0.238048)
  end

  def imbalance_ratio(vectors)
    variances = MoodVector::MOOD_HEADS.to_h do |head|
      coordinates = vectors.map { |mood| yield(mood, head) }
      [ head, population_variance(coordinates) * MoodVectors::HeadWeights.for(head) ]
    end
    total_variance = MoodVector::MOOD_HEADS.sum { |head| variances.fetch(head) }
    shares = MoodVector::MOOD_HEADS.map { |head| variances.fetch(head) / total_variance }

    shares.max / shares.min
  end

  def old_terms(query)
    album_vectors.map do |album|
      squared_distance = MoodVector::MOOD_HEADS.sum do |head|
        (album.public_send(head) - query.public_send(head))**2
      end
      Math.sqrt(squared_distance) / Math.sqrt(MoodVector::MOOD_HEADS.size)
    end
  end

  def new_terms(query)
    album_vectors.map do |album|
      described_metric_term(album:, query:)
    end
  end

  def described_metric_term(album:, query:)
    MoodVectors::MoodDistance.term(album_mood: album, query_mood: query)
  end

  def explicit_term(album:, query:, calibrate_album:)
    squared_distance = MoodVector::MOOD_HEADS.sum do |head|
      album_coordinate = if calibrate_album
        MoodVectors::HeadCalibration.album_coordinate(album, head)
      else
        album.public_send(head)
      end
      delta = album_coordinate - query.public_send(head)

      MoodVectors::HeadWeights.for(head) * delta**2
    end

    Math.sqrt(squared_distance) / MoodVectors::HeadWeights.max_distance
  end

  def mood_vector_with_all_heads(value, mood_source:)
    attributes = MoodVector::MOOD_HEADS.to_h { |head| [ head, value ] }
    MoodVector.new(**attributes, mood_source:)
  end

  def population_standard_deviation(values)
    Math.sqrt(population_variance(values))
  end

  def population_variance(values)
    mean = values.sum / values.size

    values.sum { |value| (value - mean)**2 } / values.size
  end
end
