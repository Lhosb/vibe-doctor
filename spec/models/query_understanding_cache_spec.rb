require "rails_helper"

RSpec.describe QueryUnderstandingCache do
  describe ".fetch" do
    let(:client) { instance_double(QueryUnderstandingClient) }
    let(:result) do
      QueryUnderstandingClient::Result.new(
        mood_vector: MoodVector.new(
          valence: 0.6, arousal: 0.3, danceability: 0.4, mood_acoustic: 0.7, mood_relaxed: 0.65, mood_happy: 0.55,
          mood_source: "llm_only"
        ),
        genre: "Jazz", keywords: [ "mellow" ], embedding: Array.new(1536, 0.1)
      )
    end

    it "calls the client and caches the result on first fetch" do
      allow(client).to receive(:understand).with("Warm Sunday Jazz").and_return(result)

      cache = described_class.fetch("Warm Sunday Jazz", client: client)

      expect(cache.genre).to eq("Jazz")
      expect(cache.mood_vector).to have_attributes(valence: 0.6, mood_happy: 0.55)
      expect(client).to have_received(:understand).once
    end

    it "reuses a non-expired cache row without calling the client again" do
      allow(client).to receive(:understand).and_return(result)
      described_class.fetch("Warm Sunday Jazz", client: client)

      described_class.fetch("warm sunday jazz  ", client: client) # same query, different case/whitespace

      expect(client).to have_received(:understand).once
    end

    it "calls the client again once the cache row has expired" do
      allow(client).to receive(:understand).and_return(result)
      cache = described_class.fetch("Warm Sunday Jazz", client: client)
      cache.update!(expires_at: 1.minute.ago)

      described_class.fetch("Warm Sunday Jazz", client: client)

      expect(client).to have_received(:understand).twice
    end
  end
end
