class ItunesPreviewMatcher
  SEARCH_URL = "https://itunes.apple.com/search"
  LOOKUP_URL = "https://itunes.apple.com/lookup"
  REQUEST_TIMEOUT_SECONDS = 10
  SEARCH_LIMIT = 5
  STOREFRONT_FALLBACK = "JP"

  ItunesMatch = Struct.new(:preview_url, :match_confidence, keyword_init: true)

  class Error < StandardError; end

  def initialize
    @connection = Faraday.new do |faraday|
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

  def find_previews(title:, artists:, max_tracks: 5)
    SearchTermBuilder.build_ladder(title, artists).each do |term|
      matches = matches_for_term(term, title, artists, max_tracks)
      return matches if matches.any?
    end
    []
  end

  private

  def matches_for_term(term, title, artists, max_tracks)
    default_candidate, default_confidence = best_candidate(term, title, artists, country: nil)

    if default_candidate.nil?
      jp_candidate, jp_confidence = best_candidate(term, title, artists, country: STOREFRONT_FALLBACK)
      return [] if jp_candidate.nil?

      tracks = tracks_with_previews(jp_candidate["collectionId"], country: STOREFRONT_FALLBACK)
      return build_matches(tracks, jp_confidence, max_tracks)
    end

    tracks = tracks_with_previews(default_candidate["collectionId"], country: nil)
    tracks = tracks_with_previews(default_candidate["collectionId"], country: STOREFRONT_FALLBACK) if tracks.empty?
    return build_matches(tracks, default_confidence, max_tracks) if tracks.any?

    jp_candidate, jp_confidence = best_candidate(term, title, artists, country: STOREFRONT_FALLBACK)
    return [] if jp_candidate.nil?

    tracks = tracks_with_previews(jp_candidate["collectionId"], country: STOREFRONT_FALLBACK)
    build_matches(tracks, jp_confidence, max_tracks)
  end

  def best_candidate(term, title, artists, country:)
    candidates = search_albums(term, country: country)
    return [nil, nil] if candidates.empty?

    best = candidates.max_by { |candidate| confidence(title, artists, candidate) }
    [best, confidence(title, artists, best)]
  end

  def confidence(title, artists, candidate)
    title_score = FuzzyMatch.token_set_ratio(title, candidate["collectionName"].to_s)
    artist_score = FuzzyMatch.token_set_ratio(artists.join(", "), candidate["artistName"].to_s)
    (title_score + artist_score) / 2.0
  end

  def search_albums(term, country:)
    params = { term: term, media: "music", entity: "album", limit: SEARCH_LIMIT }
    params[:country] = country if country
    get(SEARCH_URL, params)["results"] || []
  rescue Error => e
    Rails.logger.warn("iTunes search failed for '#{term}' (country=#{country}): #{e.message}")
    []
  end

  def tracks_with_previews(collection_id, country:)
    params = { id: collection_id, entity: "song" }
    params[:country] = country if country
    results = get(LOOKUP_URL, params)["results"] || []
    results.reject { |result| result["wrapperType"] == "collection" }
  rescue Error => e
    Rails.logger.warn("iTunes lookup failed for collection_id=#{collection_id} (country=#{country}): #{e.message}")
    []
  end

  def build_matches(tracks, confidence, max_tracks)
    tracks
      .select { |track| track["previewUrl"].present? }
      .sort_by { |track| track["trackNumber"].to_i }
      .first(max_tracks)
      .map { |track| ItunesMatch.new(preview_url: track["previewUrl"], match_confidence: confidence) }
  end

  def get(url, params)
    response = @connection.get(url, params) do |request|
      request.options.timeout = REQUEST_TIMEOUT_SECONDS
    end
    raise Error, "iTunes API error #{response.status}" unless response.success?

    response.body
  rescue Faraday::Error => e
    raise Error, e.message
  end
end
