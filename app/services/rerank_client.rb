class RerankClient
  MODEL = "gpt-4o-mini"

  class Error < StandardError; end

  SYSTEM_PROMPT = "You are ranking albums for a listener's request. Return the best-matching albums first."

  class Ranking < OpenAI::BaseModel
    required :album_id, Integer
    required :rerank_score, Float
    required :rationale, String
  end

  class Schema < OpenAI::BaseModel
    required :rankings, OpenAI::ArrayOf[Ranking]
  end

  def initialize(client: default_client)
    @client = client
  end

  def rerank(query_text:, ranked_candidates:)
    parsed = extract(query_text, ranked_candidates)
    raise Error, "no rerank results returned" unless parsed

    build_result(parsed, ranked_candidates)
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "rerank failed: #{e.message}"
  end

  private

  def default_client
    OpenAI::Client.new(api_key: ENV.fetch("OPENAI_API_KEY"))
  end

  def extract(query_text, ranked_candidates)
    response = @client.responses.create(
      model: MODEL,
      input: [
        { role: :system, content: SYSTEM_PROMPT },
        { role: :user, content: prompt_for(query_text, ranked_candidates) }
      ],
      text: Schema
    )

    response.output
      .select { |item| item.type == :message }
      .flat_map(&:content)
      .map(&:parsed)
      .compact
      .first
  end

  def prompt_for(query_text, ranked_candidates)
    albums_json = ranked_candidates.map { |ranked|
      { id: ranked.album.id, title: ranked.album.title, artists: ranked.album.artists, genres: ranked.album.genres }
    }.to_json

    "A listener asked for: \"#{query_text}\"\n" \
      "Rank these albums from best to worst match.\n" \
      "Albums: #{albums_json}"
  end

  def build_result(parsed, ranked_candidates)
    by_id = ranked_candidates.index_by { |ranked| ranked.album.id }

    parsed.rankings.filter_map { |ranking|
      ranked = by_id[ranking.album_id]
      next unless ranked

      { album: ranked.album, rerank_score: ranking.rerank_score, rationale: ranking.rationale }
    }.sort_by { |r| -r[:rerank_score] }
  end
end
