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

  it "keeps per-head influence below the imbalance ceiling with explicit controls (G6)", :aggregate_failures do
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
      MoodVectors::MoodDistance.term(album_mood: album, query_mood: query)
    end
  end

  def population_standard_deviation(values)
    Math.sqrt(population_variance(values))
  end

  def population_variance(values)
    mean = values.sum / values.size

    values.sum { |value| (value - mean)**2 } / values.size
  end
end
