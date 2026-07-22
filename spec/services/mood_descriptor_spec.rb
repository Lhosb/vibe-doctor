require "rails_helper"

RSpec.describe MoodDescriptor do
  def mood(**attrs)
    MoodVector.new(**{ valence: 0.5, arousal: 0.5, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5, mood_source: "essentia_itunes" }.merge(attrs))
  end

  it "returns an empty string for llm_only moods" do
    expect(described_class.render(mood(mood_source: "llm_only", valence: 0.9))).to eq("")
  end

  it "describes high valence and arousal as upbeat and high energy" do
    expect(described_class.render(mood(valence: 0.7, arousal: 0.7))).to eq("upbeat, positive mood, high energy")
  end

  it "describes low valence and arousal as melancholic and mellow" do
    expect(described_class.render(mood(valence: 0.3, arousal: 0.3))).to eq("melancholic or somber mood, mellow, low-key energy")
  end

  it "adds danceable, acoustic, relaxed, and cheerful phrases above their thresholds" do
    described = described_class.render(mood(danceability: 0.7, mood_acoustic: 0.7, mood_relaxed: 0.7, mood_happy: 0.7))
    expect(described).to eq("danceable groove, acoustic character, relaxed, easygoing feel, cheerful tone")
  end

  it "omits a valence/arousal phrase in the neutral 0.4-0.6 band" do
    expect(described_class.render(mood(valence: 0.5, arousal: 0.5))).to eq("")
  end
end
