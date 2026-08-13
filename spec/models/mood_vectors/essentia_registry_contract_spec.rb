require "rails_helper"

RSpec.describe "sonance registry contract" do
  let(:registry) { Sonance::Registry.default }

  it "contains every descriptor consumed by the mapper" do
    expect(MoodVectors::EssentiaMapper::DESCRIPTORS.size).to eq(6)
    expect(MoodVectors::EssentiaMapper::DESCRIPTORS).to all(be_in(registry.ids))
  end

  it "keeps both emomusic descriptors on the mapper's native range" do
    ranges = %i[valence_emomusic arousal_emomusic].map { |id| registry.fetch(id).native_range }

    expect(ranges).to eq(Array.new(2, MoodVectors::EssentiaMapper::EMOMUSIC_RANGE))
  end
end
