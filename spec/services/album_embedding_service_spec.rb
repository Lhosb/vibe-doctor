require "rails_helper"

RSpec.describe AlbumEmbeddingService do
  let(:album) { Album.create!(master_id: 1, title: "Kind of Blue", artists: ["Miles Davis"], year: 1959, genres: ["Jazz"], styles: ["Modal"]) }
  let(:mood_vector) { album.build_mood_vector(valence: 0.3, arousal: 0.3, mood_source: "essentia_itunes") }
  let(:vibe_card) do
    album.build_vibe_card(
      time_of_day: ["evening"], activities: ["winding down"], energy_arc: "Opens hushed.",
      texture: "Warm horns.", seasons: ["autumn"], prose: "A record for slow evenings."
    )
  end
  let(:client) { double("OpenAI::Client") } # rubocop:disable RSpec/VerifiedDoubles
  let(:embeddings) { double("embeddings") }

  subject(:service) { described_class.new(client: client) }

  def fake_embedding_data(count)
    Array.new(count) { |i| Struct.new(:embedding).new([i.to_f, 0.5]) }
  end

  before do
    allow(client).to receive(:embeddings).and_return(embeddings)
  end

  it "makes one batched embeddings call covering all four facets, in order" do
    expect(embeddings).to receive(:create) do |model:, input:|
      expect(model).to eq("text-embedding-3-small")
      expect(input.length).to eq(4)
      expect(input[0]).to include("genres include Jazz")
      expect(input[1]).to include("Opens hushed").and include("melancholic")
      expect(input[2]).to include("winding down").and include("autumn")
      expect(input[3]).to include("Kind of Blue by Miles Davis (1959)")
      Struct.new(:data).new(fake_embedding_data(4))
    end

    result = service.embed(album, mood_vector, vibe_card)

    expect(result.keys).to eq(%i[sonic emotional situational era])
    expect(result[:sonic]).to eq([0.0, 0.5])
    expect(result[:era]).to eq([3.0, 0.5])
  end

  it "falls back a blank emotional/situational facet to the era text" do
    blank_card = album.build_vibe_card
    blank_mood = album.build_mood_vector(mood_source: "llm_only")

    expect(embeddings).to receive(:create) do |input:, **|
      expect(input[1]).to eq(input[3])
      expect(input[2]).to eq(input[3])
      Struct.new(:data).new(fake_embedding_data(4))
    end

    service.embed(album, blank_mood, blank_card)
  end
end
