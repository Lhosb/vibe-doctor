class DiscogsClient
  BASE_URL = "https://api.discogs.com"
  USER_AGENT = "VibeDoctor/0.1"

  class Error < StandardError; end

  def initialize(token:)
    @token = token
    @connection = Faraday.new(url: BASE_URL) do |faraday|
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

  def collection_releases(username:)
    releases = []
    page = 1

    loop do
      body = get("/users/#{username}/collection/folders/0/releases", page: page, per_page: 100)
      releases.concat(body["releases"] || [])

      total_pages = body.dig("pagination", "pages") || 1
      break if page >= total_pages

      page += 1
    end

    releases
  end

  private

  def get(path, params)
    response = @connection.get(path, params) do |request|
      request.headers["User-Agent"] = USER_AGENT
      request.headers["Authorization"] = "Discogs token=#{@token}"
    end

    raise Error, "Discogs API error #{response.status}: #{response.body}" unless response.success?

    response.body
  end
end
