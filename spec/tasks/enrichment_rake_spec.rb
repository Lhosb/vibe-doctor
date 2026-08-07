require "rails_helper"
require "rake"

RSpec.describe "enrichment:backfill rake task" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("enrichment:backfill") }
  after { Rake::Task["enrichment:backfill"].reenable }
  let(:feature_extractor) { instance_double(MoodProbe::Extractor, verify!: true) }

  before do
    allow(MoodProbe::Extractor).to receive(:new).and_return(feature_extractor)
  end

  def mood_attrs(source:)
    MoodVector::MOOD_HEADS.index_with { 0.5 }
      .merge(mood_source: source, match_confidence: 0.9, spread: {})
  end

  def persist_mood_vector(album, source:)
    album.create_mood_vector!(mood_attrs(source:))
  end

  def stub_real_fallback_dependencies(youtube_enabled:, youtube_clips: [], youtube_error: nil)
    itunes_matcher = instance_double(ItunesPreviewMatcher)
    youtube_matcher = instance_double(YoutubeClipMatcher)
    vibe_card_generator = instance_double(VibeCardGenerator, generate: nil)
    embedding_service = instance_double(AlbumEmbeddingService)
    previews = Array.new(4) do
      ItunesPreviewMatcher::ItunesMatch.new(
        preview_url: "https://example.com/missing.m4a", match_confidence: 0.9
      )
    end
    facet_vectors = %i[sonic emotional situational era].index_with { Array.new(1536, 0.1) }
    stub_request(:get, "https://example.com/missing.m4a").to_return(status: 404)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ENABLE_YOUTUBE_GROUNDING", "true").and_return(youtube_enabled.to_s)
    allow(ItunesPreviewMatcher).to receive(:new).and_return(itunes_matcher)
    allow(YoutubeClipMatcher).to receive(:new).and_return(youtube_matcher)
    allow(VibeCardGenerator).to receive(:new).and_return(vibe_card_generator)
    allow(AlbumEmbeddingService).to receive(:new).and_return(embedding_service)
    allow(itunes_matcher).to receive(:find_previews).and_return(previews)
    allow(embedding_service).to receive(:embed).and_return(facet_vectors)
    if youtube_enabled
      allow(youtube_matcher).to receive(:find_clips).and_return(youtube_clips)
      allow(feature_extractor).to receive(:analyze).and_raise(youtube_error) if youtube_error
    end

    youtube_matcher
  end

  it "synchronously enriches every album needing enrichment and skips ones that don't" do
    pending = Album.create!(master_id: 1, title: "Pending")
    grounded = Album.create!(master_id: 2, title: "Grounded").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)

    allow(EnrichAlbumJob).to receive(:perform_now)

    Rake::Task["enrichment:backfill"].invoke

    expect(feature_extractor).to have_received(:verify!).once
    expect(EnrichAlbumJob).to have_received(:perform_now).with(pending, feature_extractor:).once
    expect(EnrichAlbumJob).not_to have_received(:perform_now).with(grounded, feature_extractor:)
  end

  it "recovers a previously failed album through the real backfill job" do
    failed = Album.create!(master_id: 1, title: "Recovered").tap(&:start_matching!).tap(&:fail_enrichment!)
    mood_grounder = instance_double(MoodGroundingService)
    vibe_card_generator = instance_double(VibeCardGenerator, generate: nil)
    embedding_service = instance_double(AlbumEmbeddingService)
    mood_attrs = MoodVector::MOOD_HEADS.index_with { 0.5 }
      .merge(mood_source: "essentia_itunes", match_confidence: 0.9, spread: {})
    facet_vectors = %i[sonic emotional situational era].index_with { Array.new(1536, 0.1) }
    allow(MoodGroundingService).to receive(:new).with(feature_extractor:).and_return(mood_grounder)
    allow(VibeCardGenerator).to receive(:new).and_return(vibe_card_generator)
    allow(AlbumEmbeddingService).to receive(:new).and_return(embedding_service)
    allow(mood_grounder).to receive(:ground) do |_album, on_matched:|
      on_matched.call
      mood_attrs
    end
    allow(embedding_service).to receive(:embed).and_return(facet_vectors)

    Rake::Task["enrichment:backfill"].invoke

    expect(failed.reload).to be_grounded
    expect(failed.mood_vector.mood_source).to eq("essentia_itunes")
  end

  it "keeps processing after one album fails, and prints a summary" do
    ok = Album.create!(master_id: 1, title: "Ok")
    broken = Album.create!(master_id: 2, title: "Broken")

    allow(EnrichAlbumJob).to receive(:perform_now) do |album|
      raise "boom" if album == broken
    end

    expect { Rake::Task["enrichment:backfill"].invoke }
      .to output(/2 albums processed.*1 succeeded.*1 failed/m).to_stdout

    expect(EnrichAlbumJob).to have_received(:perform_now).with(ok, feature_extractor:)
  end

  it "logs the per-album failure and the run summary to Rails.logger" do
    ok = Album.create!(master_id: 1, title: "Ok")
    broken = Album.create!(master_id: 2, title: "Broken")

    allow(EnrichAlbumJob).to receive(:perform_now) do |album|
      raise "boom" if album == broken
    end
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)

    Rake::Task["enrichment:backfill"].invoke

    expect(Rails.logger).to have_received(:error).with(/Album #{broken.id} \(Broken\) failed: boom/)
    expect(Rails.logger).to have_received(:info).with(/2 albums processed: 1 succeeded, 1 failed/)
    expect(EnrichAlbumJob).to have_received(:perform_now).with(ok, feature_extractor:)
  end

  it "aborts immediately when preflight fails without making iTunes HTTP calls" do
    album = Album.create!(master_id: 1, title: "Blocked")
    allow(feature_extractor).to receive(:verify!).and_raise(MoodProbe::ConfigurationError, "bad models")
    expect(EnrichAlbumJob).not_to receive(:perform_now)
    expect(Faraday).not_to receive(:get)

    expect { run_enrichment([ album ], feature_extractor:) }
      .to raise_error(MoodProbe::ConfigurationError, "bad models")
  end

  it "re-raises fatal extractor errors and stops processing later albums" do
    broken = Album.create!(master_id: 1, title: "Broken")
    untouched = Album.create!(master_id: 2, title: "Untouched")
    allow(EnrichAlbumJob).to receive(:perform_now).with(broken, feature_extractor:)
                                                   .and_raise(MoodProbe::BackendError, "protocol broke")

    expect { run_enrichment([ broken, untouched ], feature_extractor:) }
      .to output(/2 albums processed: 0 succeeded, 1 failed/).to_stdout
      .and raise_error(MoodProbe::BackendError, "protocol broke")
    expect(EnrichAlbumJob).not_to have_received(:perform_now).with(untouched, feature_extractor:)
  end

  it "aborts after five consecutive llm_only albums when YouTube is disabled" do
    albums = Array.new(5) { |index| Album.create!(master_id: index + 1, title: "Fallback #{index + 1}") }
    youtube_matcher = stub_real_fallback_dependencies(youtube_enabled: false)
    expect(youtube_matcher).not_to receive(:find_clips)

    expect { run_enrichment(albums, feature_extractor:) }
      .to raise_error(MoodProbe::FatalError, /5 consecutive albums produced llm_only/)
  end

  it "continues after per-album download and YouTube content failures" do
    albums = Array.new(3) { |index| Album.create!(master_id: index + 1, title: "Content failure #{index + 1}") }
    stub_real_fallback_dependencies(
      youtube_enabled: true,
      youtube_clips: [ "/tmp/one.m4a", "/tmp/two.m4a" ],
      youtube_error: MoodProbe::UnreadableAudioError.new("corrupt")
    )

    expect { run_enrichment(albums, feature_extractor:) }.not_to raise_error
    expect(albums.map { |album| album.reload.mood_vector.mood_source }).to all(eq("llm_only"))
  end

  it "allows fewer than five consecutive llm_only albums" do
    albums = Array.new(4) { |index| Album.create!(master_id: index + 1, title: "Fallback #{index + 1}") }
    allow(EnrichAlbumJob).to receive(:perform_now) { |album, **| persist_mood_vector(album, source: "llm_only") }

    expect { run_enrichment(albums, feature_extractor:) }.not_to raise_error
  end

  it "resets the llm_only counter after a successful audio-grounded album" do
    albums = Array.new(9) { |index| Album.create!(master_id: index + 1, title: "Album #{index + 1}") }
    sources = Array.new(4, "llm_only") + [ "essentia_itunes" ] + Array.new(4, "llm_only")
    allow(EnrichAlbumJob).to receive(:perform_now) do |album, **|
      persist_mood_vector(album, source: sources.shift)
    end

    expect { run_enrichment(albums, feature_extractor:) }.not_to raise_error
  end

  it "warns when YouTube grounding is disabled" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ENABLE_YOUTUBE_GROUNDING", "true").and_return("false")
    allow(Rails.logger).to receive(:warn)

    run_enrichment([], feature_extractor:)

    expect(Rails.logger).to have_received(:warn).with(/run-level consecutive llm_only guard is the backstop/)
  end
end

RSpec.describe "enrichment:reground_all rake task" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("enrichment:reground_all") }
  after { Rake::Task["enrichment:reground_all"].reenable }
  let(:feature_extractor) { instance_double(MoodProbe::Extractor, verify!: true) }

  before do
    allow(MoodProbe::Extractor).to receive(:new).and_return(feature_extractor)
  end

  it "resets every album to pending and re-enriches all of them, including already-grounded ones" do
    grounded = Album.create!(master_id: 1, title: "Grounded").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)
    pending = Album.create!(master_id: 2, title: "Pending")

    allow(EnrichAlbumJob).to receive(:perform_now)

    Rake::Task["enrichment:reground_all"].invoke

    expect(grounded.reload).to be_pending
    expect(EnrichAlbumJob).to have_received(:perform_now).with(grounded, feature_extractor:).once
    expect(EnrichAlbumJob).to have_received(:perform_now).with(pending, feature_extractor:).once
  end

  it "preflights before resetting any album" do
    grounded = Album.create!(master_id: 1, title: "Grounded").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)
    allow(feature_extractor).to receive(:verify!).and_raise(MoodProbe::ConfigurationError, "bad models")

    expect { Rake::Task["enrichment:reground_all"].invoke }
      .to raise_error(MoodProbe::ConfigurationError, "bad models")
    expect(grounded.reload).to be_grounded
  end
end
