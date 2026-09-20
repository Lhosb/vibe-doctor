require "rails_helper"

RSpec.describe MoodVectors::HeadCalibration do
  describe ".album_coordinate" do
    let(:mood_vector) do
      MoodVector.new(
        valence: 0.344,
        arousal: 0.674,
        danceability: 0.42,
        mood_acoustic: 0.31,
        mood_relaxed: 0.86,
        mood_happy: 0.57
      )
    end

    it "uses a 3.0..7.0 band for emomusic heads (G1)" do
      expect(described_class::BAND_MIN).to eq(3.0)
      expect(described_class::BAND_MAX).to eq(7.0)
      expect(described_class.album_coordinate(mood_vector, :valence)).to be_within(1e-12).of(0.188)
      expect(described_class.album_coordinate(mood_vector, :arousal)).to be_within(1e-12).of(0.848)
    end

    it "passes through musicnn heads unchanged (G1)" do
      expect(described_class.album_coordinate(mood_vector, :danceability)).to eq(0.42)
      expect(described_class.album_coordinate(mood_vector, :mood_acoustic)).to eq(0.31)
      expect(described_class.album_coordinate(mood_vector, :mood_relaxed)).to eq(0.86)
      expect(described_class.album_coordinate(mood_vector, :mood_happy)).to eq(0.57)
    end

    it "does not clamp scoring-time calibrated coordinates (G2)", :aggregate_failures do
      below_band = MoodVector.new(valence: 0.1)
      above_band = MoodVector.new(valence: 0.95)

      expect(described_class.album_coordinate(below_band, :valence)).to be_within(1e-12).of(-0.3)
      expect(described_class.album_coordinate(above_band, :valence)).to be_within(1e-12).of(1.4)
    end

    it "preserves neutral 0.5 across all heads (G10)" do
      neutral = MoodVector.new(
        valence: 0.5,
        arousal: 0.5,
        danceability: 0.5,
        mood_acoustic: 0.5,
        mood_relaxed: 0.5,
        mood_happy: 0.5
      )

      MoodVector::MOOD_HEADS.each do |head|
        expect(described_class.album_coordinate(neutral, head)).to be_within(1e-12).of(0.5)
      end
    end
  end
end
