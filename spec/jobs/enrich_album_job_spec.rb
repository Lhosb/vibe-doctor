require "rails_helper"

RSpec.describe EnrichAlbumJob, type: :job do
  let(:album) { Album.create!(master_id: 1, title: "Kind of Blue", artists: ["Miles Davis"], year: 1959, genres: ["Jazz"]) }
  let(:mood_grounder) { instance_double(MoodGroundingService) }
  let(:vibe_card_generator) { instance_double(VibeCardGenerator) }
  let(:embedding_service) { instance_double(AlbumEmbeddingService) }
  let(:mood_attrs) do
    { valence: 0.3, arousal: 0.3, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5,
      mood_source: "essentia_itunes", match_confidence: 0.9, spread: { valence: 0.1 } }
  end
  let(:card_schema) do
    VibeCardGenerator::Schema.new(
      time_of_day: ["evening"], activities: ["winding down"], energy_arc: "Hushed then loosens.",
      texture: "Warm horns.", seasons: ["autumn"], prose: "A record for slow evenings."
    )
  end
  let(:facet_vectors) do
    {
      sonic: Array.new(1536, 0.1),
      emotional: Array.new(1536, 0.2),
      situational: Array.new(1536, 0.3),
      era: Array.new(1536, 0.4)
    }
  end

  def perform
    described_class.new.perform(
      album, mood_grounder: mood_grounder, vibe_card_generator: vibe_card_generator, embedding_service: embedding_service
    )
  end

  it "walks the album through pending -> matching_audio -> extracting_features -> grounded and persists all three records" do
    allow(mood_grounder).to receive(:ground) do |_album, on_matched:|
      on_matched.call
      mood_attrs
    end
    allow(vibe_card_generator).to receive(:generate).and_return(card_schema)
    allow(embedding_service).to receive(:embed).and_return(facet_vectors)

    perform

    album.reload
    expect(album).to be_grounded
    expect(album.mood_vector.mood_source).to eq("essentia_itunes")
    expect(album.mood_vector.spread).to eq("valence" => 0.1)
    expect(album.vibe_card.energy_arc).to eq("Hushed then loosens.")
    expect(album.embedding.sonic).to eq(Array.new(1536, 0.1))
  end

  it "falls back to an empty VibeCard when generation returns nil" do
    allow(mood_grounder).to receive(:ground) do |_album, on_matched:|
      on_matched.call
      mood_attrs
    end
    allow(vibe_card_generator).to receive(:generate).and_return(nil)
    allow(embedding_service).to receive(:embed).and_return(facet_vectors)

    perform

    expect(album.reload.vibe_card.prose).to eq("")
    expect(album).to be_grounded
  end

  it "grounds albums that never match audio by moving directly into extraction before persisting the llm_only fallback" do
    allow(mood_grounder).to receive(:ground).and_return(mood_attrs.merge(mood_source: "llm_only", match_confidence: 0.0, spread: {}))
    allow(vibe_card_generator).to receive(:generate).and_return(nil)
    allow(embedding_service).to receive(:embed).and_return(facet_vectors)

    perform

    album.reload
    expect(album).to be_grounded
    expect(album.mood_vector.mood_source).to eq("llm_only")
  end

  it "marks the album failed and re-raises on an unexpected error" do
    allow(mood_grounder).to receive(:ground) do |_album, on_matched:|
      on_matched.call
      mood_attrs
    end
    allow(vibe_card_generator).to receive(:generate).and_return(card_schema)
    allow(embedding_service).to receive(:embed).and_raise(StandardError, "OpenAI is down")

    expect { perform }.to raise_error(StandardError, "OpenAI is down")
    expect(album.reload).to be_failed
  end
end
