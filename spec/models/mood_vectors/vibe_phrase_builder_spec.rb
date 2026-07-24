require "rails_helper"

RSpec.describe MoodVectors::VibePhraseBuilder do
  def mood(**overrides)
    MoodVector.new(
      valence: 0.5, arousal: 0.5, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5,
      **overrides
    )
  end

  it "excludes a head sitting exactly at the neutral midpoint" do
    expect(described_class.new(mood(valence: 0.5)).call).to eq("")
  end

  it "excludes a head at the low/mid boundary (0.4 is not distinctive)" do
    expect(described_class.new(mood(valence: 0.4)).call).to eq("")
  end

  it "includes a head just below the low boundary as the low-band adjective" do
    expect(described_class.new(mood(valence: 0.39)).call).to eq("somber")
  end

  it "excludes a head at the high/mid boundary (0.6 is not distinctive)" do
    expect(described_class.new(mood(valence: 0.6)).call).to eq("")
  end

  it "includes a head just above the high boundary as the high-band adjective" do
    expect(described_class.new(mood(valence: 0.61)).call).to eq("sunny")
  end

  it "selects only the 2 most distinctive heads out of several distinctive ones" do
    phrase_mood = mood(valence: 0.2, arousal: 0.35, mood_happy: 0.1)
    expect(described_class.new(phrase_mood).call).to eq("brooding somber")
  end

  it "joins the selected adjectives with the album's genre" do
    phrase_mood = mood(valence: 0.2, arousal: 0.35, mood_happy: 0.1)
    expect(described_class.new(phrase_mood, genre: "Jazz").call).to eq("brooding somber — Jazz")
  end

  it "falls back to the genre alone when nothing is distinctive" do
    expect(described_class.new(mood, genre: "Techno").call).to eq("Techno")
  end

  it "falls back to a single adjective (no separator) when only one head is distinctive" do
    expect(described_class.new(mood(valence: 0.2), genre: "Techno").call).to eq("somber — Techno")
  end
end
