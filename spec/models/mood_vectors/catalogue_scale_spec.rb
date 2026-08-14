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

  it "includes a drift-check SQL query and tolerance declaration for reviewable reproducibility" do
    expect(described_class::DRIFT_CHECK_SQL).to include("WHERE mood_source LIKE 'essentia%'")
    expect(described_class::DRIFT_CHECK_SQL).to include("stddev_pop(danceability)")
    expect(described_class::DRIFT_CHECK_SQL).to include("stddev_pop(mood_relaxed)")
    expect(described_class::DRIFT_TOLERANCE_RELATIVE).to eq(0.25)
  end
end
