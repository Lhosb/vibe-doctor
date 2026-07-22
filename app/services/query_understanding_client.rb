class QueryUnderstandingClient
  MODEL = "gpt-4o-mini"
  EMBEDDING_MODEL = "text-embedding-3-small"

  class Error < StandardError; end

  SYSTEM_PROMPT = (
    "A music listener describes what they want to hear. Extract their intent as structured mood/genre data. " \
    "valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy are floats from 0.0 to 1.0, " \
    "matching the same audio-mood dimensions Essentia extracts from tracks. " \
    "genre: a single best-fit genre string, or null if none is implied. " \
    "keywords: 2-5 short strings capturing the listener's phrasing."
  ).freeze

  class Schema < OpenAI::BaseModel
    required :valence, Float
    required :arousal, Float
    required :danceability, Float
    required :mood_acoustic, Float
    required :mood_relaxed, Float
    required :mood_happy, Float
    required :genre, String, nil?: true
    required :keywords, OpenAI::ArrayOf[String]
  end

  Result = Struct.new(:mood_vector, :genre, :keywords, :embedding, keyword_init: true)

  def initialize(client: default_client)
    @client = client
  end

  def understand(query_text)
    parsed = extract_intent(query_text)
    raise Error, "no intent returned for query" unless parsed

    Result.new(
      mood_vector: MoodVector.new(
        valence: parsed.valence, arousal: parsed.arousal, danceability: parsed.danceability,
        mood_acoustic: parsed.mood_acoustic, mood_relaxed: parsed.mood_relaxed, mood_happy: parsed.mood_happy,
        mood_source: "llm_only"
      ),
      genre: parsed.genre,
      keywords: parsed.keywords,
      embedding: embed(query_text)
    )
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "query understanding failed: #{e.message}"
  end

  private

  def default_client
    OpenAI::Client.new(api_key: ENV.fetch("OPENAI_API_KEY"))
  end

  def extract_intent(query_text)
    response = @client.responses.create(
      model: MODEL,
      input: [
        { role: :system, content: SYSTEM_PROMPT },
        { role: :user, content: query_text }
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

  def embed(query_text)
    @client.embeddings.create(model: EMBEDDING_MODEL, input: [query_text]).data.first.embedding
  end
end
