require "rails_helper"

RSpec.describe MoodGroundingService do
  let(:album) { Album.create!(master_id: 1, title: "Kind of Blue", artists: ["Miles Davis"]) }
  let(:itunes_matcher) { instance_double(ItunesPreviewMatcher) }
  let(:youtube_matcher) { instance_double(YoutubeClipMatcher) }
  let(:feature_extractor) { instance_double(EssentiaFeatureExtractor) }
  let(:track) { { valence: 0.5, arousal: 0.5, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5 } }

  subject(:service) do
    described_class.new(itunes_matcher: itunes_matcher, youtube_matcher: youtube_matcher, feature_extractor: feature_extractor)
  end

  def itunes_match(url, confidence)
    ItunesPreviewMatcher::ItunesMatch.new(preview_url: url, match_confidence: confidence)
  end

  before do
    stub_request(:get, "https://example.com/preview.m4a").to_return(status: 200, body: "fake audio")
  end

  it "aggregates mean and population-stddev spread across multiple iTunes tracks, calling on_matched once" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9)]
    )
    allow(feature_extractor).to receive(:analyze).and_return(
      track.merge(valence: 0.2), track.merge(valence: 0.8)
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
    allow(itunes_matcher).to receive(:find_previews).and_return([itunes_match("https://example.com/preview.m4a", 0.9)])
    allow(feature_extractor).to receive(:analyze).and_return(track)

    result = service.ground(album)

    expect(result[:spread].values).to all(eq(0.0))
  end

  it "falls through to YouTube when iTunes has no previews, without calling YouTube's matcher a second time" do
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    allow(youtube_matcher).to receive(:find_clips).and_return(["/tmp/clip.m4a"])
    allow(feature_extractor).to receive(:analyze).with("/tmp/clip.m4a").and_return(track)
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

  it "falls through to llm_only when every matched track fails analysis" do
    allow(itunes_matcher).to receive(:find_previews).and_return([itunes_match("https://example.com/preview.m4a", 0.9)])
    allow(feature_extractor).to receive(:analyze).and_raise(EssentiaFeatureExtractor::Error, "boom")
    allow(youtube_matcher).to receive(:find_clips).and_return([])

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end

  it "grounds from the survivors when some but not all tracks fail analysis" do
    allow(itunes_matcher).to receive(:find_previews).and_return(
      [itunes_match("https://example.com/preview.m4a", 0.9), itunes_match("https://example.com/preview.m4a", 0.9)]
    )
    call_count = 0
    allow(feature_extractor).to receive(:analyze) do
      call_count += 1
      call_count == 1 ? raise(EssentiaFeatureExtractor::Error, "boom") : track
    end

    expect(service.ground(album)[:mood_source]).to eq("essentia_itunes")
  end

  it "skips YouTube entirely when disabled" do
    service = described_class.new(itunes_matcher: itunes_matcher, youtube_matcher: youtube_matcher,
                                   feature_extractor: feature_extractor, enable_youtube_grounding: false)
    allow(itunes_matcher).to receive(:find_previews).and_return([])
    expect(youtube_matcher).not_to receive(:find_clips)

    expect(service.ground(album)[:mood_source]).to eq("llm_only")
  end
end
