require "rails_helper"

RSpec.describe MoodVectors::EssentiaMapper do
  describe "#call" do
    def descriptors_with(**overrides)
      {
        valence_emomusic: 5.0,
        arousal_emomusic: 5.0,
        danceability: 0.2,
        mood_acoustic: 0.3,
        mood_relaxed: 0.4,
        mood_happy: 0.6
      }.merge(overrides)
    end

    it "maps native descriptor values to symbol-keyed mood heads" do
      # The arousal override keeps valence/arousal transposition detectable despite equal helper defaults.
      descriptors = descriptors_with(arousal_emomusic: 3.0)

      expect(described_class.new.call(descriptors)).to eq(
        valence: 0.5,
        arousal: 0.25,
        danceability: 0.2,
        mood_acoustic: 0.3,
        mood_relaxed: 0.4,
        mood_happy: 0.6
      )
    end

    {
      9.4 => 1.0,
      9.0 => 1.0,
      5.0 => 0.5,
      3.0 => 0.25,
      1.0 => 0.0,
      0.6 => 0.0
    }.each do |native_value, expected_value|
      it "maps native emomusic value #{native_value} to #{expected_value}" do
        result = described_class.new.call(descriptors_with(valence_emomusic: native_value))

        expect(result.fetch(:valence)).to eq(expected_value)
      end
    end

    it "clamps arousal emomusic values outside the native range", :aggregate_failures do
      above_range = described_class.new.call(descriptors_with(arousal_emomusic: 9.4))
      below_range = described_class.new.call(descriptors_with(arousal_emomusic: 0.6))

      expect(above_range.fetch(:arousal)).to eq(1.0)
      expect(below_range.fetch(:arousal)).to eq(0.0)
    end

    it "clamps softmax heads to the MoodVector range", :aggregate_failures do
      descriptors = descriptors_with(
        danceability: 1.1,
        mood_acoustic: -0.1,
        mood_relaxed: 1.1,
        mood_happy: -0.1
      )

      result = described_class.new.call(descriptors)

      expect(result.fetch(:danceability)).to eq(1.0)
      expect(result.fetch(:mood_acoustic)).to eq(0.0)
      expect(result.fetch(:mood_relaxed)).to eq(1.0)
      expect(result.fetch(:mood_happy)).to eq(0.0)
    end

    it "rejects a missing descriptor" do
      descriptors = descriptors_with.except(:mood_happy)

      expect { described_class.new.call(descriptors) }
        .to raise_error(ArgumentError, "missing descriptors: mood_happy")
    end

    it "rejects an unexpected descriptor" do
      descriptors = descriptors_with(bpm: 120.0)

      expect { described_class.new.call(descriptors) }
        .to raise_error(ArgumentError, "unexpected descriptors: bpm")
    end
  end
end
