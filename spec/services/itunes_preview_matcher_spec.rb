require "rails_helper"

RSpec.describe ItunesPreviewMatcher do
  subject(:matcher) { described_class.new }

  # Real iTunes API responses are served as text/javascript, not application/json.
  ITUNES_CONTENT_TYPE = "text/javascript; charset=utf-8"

  def stub_search(term, country: nil, results:)
    params = { term: term, media: "music", entity: "album", limit: "5" }
    params[:country] = country if country
    stub_request(:get, "https://itunes.apple.com/search")
      .with(query: params)
      .to_return(status: 200, headers: { "Content-Type" => ITUNES_CONTENT_TYPE }, body: { results: results }.to_json)
  end

  def stub_lookup(collection_id, country: nil, results:)
    params = { id: collection_id.to_s, entity: "song" }
    params[:country] = country if country
    stub_request(:get, "https://itunes.apple.com/lookup")
      .with(query: params)
      .to_return(status: 200, headers: { "Content-Type" => ITUNES_CONTENT_TYPE }, body: { results: results }.to_json)
  end

  it "returns preview URLs sorted by track number, capped at max_tracks, sharing one confidence" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: [
      { "wrapperType" => "track", "trackNumber" => 2, "previewUrl" => "https://example.com/2.m4a" },
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/1.m4a" },
      { "wrapperType" => "collection" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/1.m4a", "https://example.com/2.m4a"])
    expect(matches.map(&:match_confidence).uniq).to eq([1.0])
  end

  it "caps results at max_tracks" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: (1..7).map { |n| { "wrapperType" => "track", "trackNumber" => n, "previewUrl" => "https://example.com/#{n}.m4a" } })

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 3)

    expect(matches.length).to eq(3)
  end

  it "filters out tracks with no preview URL" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => nil },
      { "wrapperType" => "track", "trackNumber" => 2, "previewUrl" => "https://example.com/2.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/2.m4a"])
  end

  it "falls back to the JP storefront when the default-storefront lookup is empty" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: [])
    stub_lookup(1, country: "JP", results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/jp.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/jp.m4a"])
  end

  it "falls back to the JP storefront when the default-storefront tracks have no preview URLs" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => nil }
    ])
    stub_lookup(1, country: "JP", results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/jp.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/jp.m4a"])
  end

  it "falls back to a JP-storefront candidate when the default candidate has no preview URLs in either storefront" do
    stub_search("Miles Davis Kind of Blue", results: [
      { "collectionId" => 1, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(1, results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => nil }
    ])
    stub_lookup(1, country: "JP", results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => nil }
    ])
    stub_search("Miles Davis Kind of Blue", country: "JP", results: [
      { "collectionId" => 2, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(2, country: "JP", results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/jp2.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/jp2.m4a"])
  end

  it "falls back to a JP-storefront search when the default-storefront search is empty" do
    stub_search("Miles Davis Kind of Blue", results: [])
    stub_search("Miles Davis Kind of Blue", country: "JP", results: [
      { "collectionId" => 2, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(2, country: "JP", results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/jp.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/jp.m4a"])
  end

  it "falls through the ladder to the title-only rung when the artist+title rung has zero results" do
    stub_search("Miles Davis Kind of Blue", results: [])
    stub_search("Miles Davis Kind of Blue", country: "JP", results: [])
    stub_search("Kind of Blue", results: [
      { "collectionId" => 3, "collectionName" => "Kind of Blue", "artistName" => "Miles Davis" }
    ])
    stub_lookup(3, results: [
      { "wrapperType" => "track", "trackNumber" => 1, "previewUrl" => "https://example.com/3.m4a" }
    ])

    matches = matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)

    expect(matches.map(&:preview_url)).to eq(["https://example.com/3.m4a"])
  end

  it "returns an empty array when no rung ever yields a preview" do
    stub_search("Miles Davis Kind of Blue", results: [])
    stub_search("Miles Davis Kind of Blue", country: "JP", results: [])
    stub_search("Kind of Blue", results: [])
    stub_search("Kind of Blue", country: "JP", results: [])

    expect(matcher.find_previews(title: "Kind of Blue", artists: ["Miles Davis"], max_tracks: 5)).to eq([])
  end
end
