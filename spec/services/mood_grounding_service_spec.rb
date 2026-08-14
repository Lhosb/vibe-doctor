require "rails_helper"

RSpec.describe MoodGroundingService do
  let(:album) { Album.create!(master_id: 1, title: "Kind of Blue", artists: [ "Miles Davis" ]) }
  let(:itunes_matcher) { instance_double(ItunesPreviewMatcher) }
  let(:youtube_matcher) { instance_double(YoutubeClipMatcher) }
  let(:feature_extractor) { instance_double(Sonance::Extractor) }
  let(:raw_track) do
    {
      valence_emomusic: 5.0,
      arousal_emomusic: 5.0,
      danceability_musicnn: 0.5,
      mood_acoustic_musicnn: 0.5,
      mood_relaxed_musicnn: 0.5,
      mood_happy_musicnn: 0.5
    }
  end

  subject(:service) do
    described_class.new(itunes_matcher: itunes_matcher, youtube_matcher: youtube_matcher, feature_extractor: feature_extractor)
  end

  def itunes_match(url, confidence)
    ItunesPreviewMatcher::ItunesMatch.new(preview_url: url, match_confidence: confidence)
  end

  def analysis(overrides = {})
    Sonance::AnalysisBuilder.new(registry: Sonance::Registry.default).call(
      requested: MoodVectors::EssentiaMapper::DESCRIPTORS,
      raw_values: raw_track.merge(overrides)
    )
  end

  before do
    stub_request(:get, "https://example.com/preview.m4a").to_return(status: 200, body: "fake audio")
  end

  it "aggregates mean and population-stddev spread across multiple iTunes tracks, calling on_matched once" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    allow(feature_extractor).to receive(:analyze).and_return(
      analysis(valence_emomusic: 2.6), analysis(valence_emomusic: 7.4)
    )
    matched_calls = 0

    result = service.ground(album, on_matched: -> { matched_calls += 1 })

    expect(result[:mood_source]).to eq("essentia_itunes")
    expect(result[:match_confidence]).to eq(0.9)
    expect(result[:valence]).to eq(0.5)
    expect(result[:spread][:valence]).to eq(0.3)
    expect(matched_calls).to eq(1)
  end

  it "has zero spread for a single matched track" do
    allow(itunes_matcher).to receive(:find_previews).and_return([ itunes_match("https://example.com/preview.m4a", 0.9) ])
    allow(feature_extractor).to receive(:analyze).and_return(analysis)

    result = service.ground(album)

    expect(result[:spread].values).to all(eq(0.0))
  end

  it "falls through to YouTube when iTunes has no previews, without calling YouTube's matcher a second time" do
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/clip.m4a" ])
    allow(feature_extractor).to receive(:analyze)
      .with("/tmp/clip.m4a", descriptors: MoodVectors::EssentiaMapper::DESCRIPTORS)
      .and_return(analysis)
    allow(File).to receive(:exist?).with("/tmp/clip.m4a").and_return(true)
    allow(File).to receive(:delete).with("/tmp/clip.m4a")

    result = service.ground(album)

    expect(result[:mood_source]).to eq("essentia_youtube")
    expect(result[:match_confidence]).to eq(1.0)
  end

  it "falls through to llm_only when both tiers yield nothing" do
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    allow(youtube_matcher).to receive(:find_clips).and_return([])

    result = service.ground(album)

    expect(result[:mood_source]).to eq("llm_only")
    expect(result[:match_confidence]).to eq(0.0)
    expect(result[:spread]).to eq({})
    expect(result[:valence]).to eq(0.5)
  end

  it "does not escalate when only one matched track fails" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::UnreadableAudioError, "corrupt")
    allow(youtube_matcher).to receive(:find_clips).and_return([])

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "logs and skips an out-of-sanity-range track" do
    preview_url = "https://example.com/preview.m4a"
    allow(itunes_matcher).to receive(:find_previews).and_return([ itunes_match(preview_url, 0.9) ])
    allow(feature_extractor).to receive(:analyze)
      .and_raise(Sonance::MalformedOutputError, "valence_emomusic is outside sanity range -3.0..13.0")
    allow(youtube_matcher).to receive(:find_clips).and_return([])
    allow(Rails.logger).to receive(:error)

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
    expect(Rails.logger).to have_received(:error)
      .with(
        /album_id=#{album.id}.*source=iTunes.*error=Sonance::MalformedOutputError.*attempted=1 contributing=0/
      )
  end

  it "tries YouTube after multiple iTunes tracks fail uniformly" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/clip.m4a" ])
    allow(feature_extractor).to receive(:analyze)
      .with("/tmp/clip.m4a", descriptors: MoodVectors::EssentiaMapper::DESCRIPTORS)
      .and_return(analysis)

    expect(service.ground(album)[:mood_source]).to eq("essentia_youtube")
    expect(youtube_matcher).to have_received(:find_clips)
  end

  it "does not escalate Faraday failures even when YouTube analysis fails uniformly" do
    stub_request(:get, "https://example.com/missing.m4a").to_return(status: 404)
    allow(itunes_matcher).to receive(:find_previews).and_return(
      Array.new(2) { itunes_match("https://example.com/missing.m4a", 0.9) }
    )
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/one.m4a", "/tmp/two.m4a" ])
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "counts only tracks that reached the extractor when download and probe failures are mixed" do
    stub_request(:get, "https://example.com/mixed.m4a").to_return(
      { status: 404 },
      { status: 404 },
      { status: 200, body: "audio" },
      { status: 200, body: "audio" }
    )
    allow(itunes_matcher).to receive(:find_previews).and_return(
      Array.new(4) { itunes_match("https://example.com/mixed.m4a", 0.9) }
    )
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/one.m4a", "/tmp/two.m4a" ])
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::UnreadableAudioError, "corrupt")

    expect { service.ground(album) }
      .to raise_error(
        MoodGroundingService::SystematicTrackFailure,
        "2 iTunes tracks failed with Sonance::UnreadableAudioError; " \
        "2 YouTube tracks failed with Sonance::UnreadableAudioError"
      )
  end

  it "uses YouTube when every iTunes preview download fails" do
    stub_request(:get, "https://example.com/missing.m4a").to_return(status: 404)
    allow(itunes_matcher).to receive(:find_previews).and_return(
      Array.new(2) { itunes_match("https://example.com/missing.m4a", 0.9) }
    )
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/clip.m4a" ])
    allow(feature_extractor).to receive(:analyze)
      .with("/tmp/clip.m4a", descriptors: MoodVectors::EssentiaMapper::DESCRIPTORS)
      .and_return(analysis)

    expect(service.ground(album)[:mood_source]).to eq("essentia_youtube")
  end

  it "records Faraday failures as track evidence" do
    track_omissions = []
    stub_request(:get, "https://example.com/missing.m4a").to_return(status: 404)

    result = service.send(
      :analyze_remote_track, "https://example.com/missing.m4a", track_omissions:, track_number: 1
    )

    expect(result).to be_nil
    expect(track_omissions.map(&:error)).to contain_exactly(an_instance_of(Faraday::Error))
  end

  it "degrades silently when YouTube is disabled after uniform iTunes failures" do
    disabled_service = described_class.new(
      itunes_matcher:, youtube_matcher:, feature_extractor:, enable_youtube_grounding: false
    )
    allow(itunes_matcher).to receive(:find_previews).and_return(
      Array.new(2) { itunes_match("https://example.com/preview.m4a", 0.9) }
    )
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")
    expect(youtube_matcher).not_to receive(:find_clips)

    expect(disabled_service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "degrades silently when uniform iTunes failures find no YouTube clips" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      Array.new(2) { itunes_match("https://example.com/preview.m4a", 0.9) }
    )
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")
    allow(youtube_matcher).to receive(:find_clips).and_return([])

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "degrades silently when only YouTube fails uniformly" do
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/one.m4a", "/tmp/two.m4a" ])
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "aggregates surviving tracks and logs omission counts when malformed output skips a track" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    call_count = 0
    allow(feature_extractor).to receive(:analyze) do
      call_count += 1
      call_count == 1 ? raise(Sonance::MalformedOutputError, "bad valence") : analysis(valence_emomusic: 7.4)
    end
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)

    result = service.ground(album)

    expect(result[:mood_source]).to eq("essentia_itunes")
    expect(result[:valence]).to eq(0.8)
    expect(result[:spread][:valence]).to eq(0.0)
    expect(Rails.logger).to have_received(:error)
      .with(
        /album_id=#{album.id}.*source=iTunes.*track_number=1.*error=Sonance::MalformedOutputError.*attempted=2 contributing=1/
      )
    expect(Rails.logger).to have_received(:info)
      .with(/album_id=#{album.id}.*source=iTunes.*attempted=2 contributing=1/)
  end

  it "does not escalate when all matched tracks fail with different error classes" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    errors = [ Sonance::InferenceError.new("inference"), Sonance::TimeoutError.new("timeout") ]
    allow(feature_extractor).to receive(:analyze) { raise errors.shift }
    allow(youtube_matcher).to receive(:find_clips).and_return([])

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "propagates fatal extractor errors" do
    allow(itunes_matcher).to receive(:find_previews).and_return([ itunes_match("https://example.com/preview.m4a", 0.9) ])
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::ConfigurationError, "bad models")

    expect { service.ground(album) }.to raise_error(Sonance::ConfigurationError, "bad models")
  end

  it "escalates only after both sources fail uniformly across multiple tracks" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [ itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9) ]
    )
    allow(youtube_matcher).to receive(:find_clips).and_return([ "/tmp/one.m4a", "/tmp/two.m4a" ])
    allow(feature_extractor).to receive(:analyze).and_raise(Sonance::InferenceError, "boom")
    allow(File).to receive(:exist?).and_return(false)

    expect { service.ground(album) }
      .to raise_error(
        MoodGroundingService::SystematicTrackFailure,
        "2 iTunes tracks failed with Sonance::InferenceError; " \
        "2 YouTube tracks failed with Sonance::InferenceError"
      )
    expect(youtube_matcher).to have_received(:find_clips)
  end

  it "deletes every downloaded YouTube clip when a fatal analysis error aborts the loop" do
    allow(itunes_matcher).to receive(:find_previews).and_return([])

    Dir.mktmpdir do |directory|
      paths = %w[one.m4a two.m4a].map { |name| File.join(directory, name) }
      paths.each { |path| File.binwrite(path, "audio") }
      allow(youtube_matcher).to receive(:find_clips).and_return(paths)
      allow(feature_extractor).to receive(:analyze)
        .with(paths.first, descriptors: MoodVectors::EssentiaMapper::DESCRIPTORS)
        .and_raise(Sonance::ConfigurationError, "bad models")

      expect { service.ground(album) }.to raise_error(Sonance::ConfigurationError, "bad models")
      expect(paths).to all(satisfy { |path| !File.exist?(path) })
    end
  end

  it "skips YouTube entirely when disabled" do
    service = described_class.new(itunes_matcher: itunes_matcher, youtube_matcher: youtube_matcher,
                                   feature_extractor: feature_extractor, enable_youtube_grounding: false)
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    expect(youtube_matcher).not_to receive(:find_clips)

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end
end
