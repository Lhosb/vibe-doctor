require "rails_helper"

RSpec.describe MoodVectors::HeadWeights do
  describe ".validate!" do
    it "keeps WEIGHTS order aligned with MoodVector::MOOD_HEADS (R6)" do
      expect(described_class::WEIGHTS.keys).to eq(MoodVector::MOOD_HEADS)
    end

    it "requires WEIGHTS to be frozen (G3)" do
      unfrozen = described_class::WEIGHTS.dup

      expect do
        described_class.validate!(unfrozen)
      end.to raise_error(ArgumentError, /must be frozen/)
    end

    it "requires exact key set equality with mood heads (G3)" do
      invalid = described_class::WEIGHTS.except(:mood_relaxed).freeze

      expect do
        described_class.validate!(invalid)
      end.to raise_error(ArgumentError, /keys must match/)
    end

    it "requires finite and positive values (G3)", :aggregate_failures do
      expect do
        described_class.validate!(described_class::WEIGHTS.merge(valence: -1.0).freeze)
      end.to raise_error(ArgumentError, /valence/)

      expect do
        described_class.validate!(described_class::WEIGHTS.merge(valence: 0.0).freeze)
      end.to raise_error(ArgumentError, /valence/)

      expect do
        described_class.validate!(described_class::WEIGHTS.merge(valence: Float::NAN).freeze)
      end.to raise_error(ArgumentError, /valence/)
    end
  end

  describe ".max_distance" do
    it "is derived live from WEIGHTS rather than hardcoded (G4)" do
      expect(described_class.max_distance).to eq(Math.sqrt(described_class::WEIGHTS.values.sum))

      doubled_weights = described_class::WEIGHTS.transform_values { |value| value * 2.0 }.freeze
      stub_const("MoodVectors::HeadWeights::WEIGHTS", doubled_weights)

      expect(described_class.max_distance).to eq(Math.sqrt(doubled_weights.values.sum))
    end

    it "keeps normalized mood term invariant under uniform weight scaling (G4)" do
      deltas = {
        valence: 0.3,
        arousal: 0.2,
        danceability: 0.6,
        mood_acoustic: 0.4,
        mood_happy: 0.1,
        mood_relaxed: 0.5
      }

      base = normalized_term_runtime(described_class::WEIGHTS, deltas)
      doubled = normalized_term_runtime(described_class::WEIGHTS.transform_values { |value| value * 2.0 }.freeze, deltas)

      expect(doubled).to be_within(1e-12).of(base)
    end
  end

  def normalized_term_runtime(weights, deltas)
    stub_const("MoodVectors::HeadWeights::WEIGHTS", weights)

    distance = Math.sqrt(MoodVector::MOOD_HEADS.sum { |head| described_class.for(head) * deltas.fetch(head)**2 })
    distance / described_class.max_distance
  end
end
