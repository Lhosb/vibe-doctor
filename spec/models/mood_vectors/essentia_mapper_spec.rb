require "rails_helper"

RSpec.describe MoodVectors::EssentiaMapper do
  describe "#call" do
    def descriptors_with(valence:)
      {
        "valence_emomusic" => valence,
        "arousal_emomusic" => 5.0,
        "danceability" => 0.2,
        "mood_acoustic" => 0.3,
        "mood_relaxed" => 0.4,
        "mood_happy" => 0.6
      }
    end

    it "maps native descriptor values to symbol-keyed mood heads" do
      descriptors = descriptors_with(valence: 5.0).merge("arousal_emomusic" => 3.0)

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
        result = described_class.new.call(descriptors_with(valence: native_value))

        expect(result.fetch(:valence)).to eq(expected_value)
      end
    end

    it "clamps softmax heads to the MoodVector range" do
      descriptors = descriptors_with(valence: 5.0).merge(
        "danceability" => 1.1,
        "mood_acoustic" => -0.1
      )

      result = described_class.new.call(descriptors)

      expect(result.fetch(:danceability)).to eq(1.0)
      expect(result.fetch(:mood_acoustic)).to eq(0.0)
    end
  end
end
