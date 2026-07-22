class VibeCardGenerator
  MODEL = "gpt-4o-mini"
  MAX_OUTPUT_TOKENS = 300

  SYSTEM_PROMPT = (
    "You are a music expert writing a listening-context card for a vinyl album. " \
    "Ground every claim in the given genres, styles, and era; if the album is obscure, " \
    "describe what is typical for its genre and era rather than inventing specifics. " \
    "time_of_day: choose from morning, midday, afternoon, evening, late night. " \
    "activities: 2-4 concrete activities (e.g. 'making coffee', 'cooking dinner', " \
    "'getting ready to go out', 'winding down'). " \
    "energy_arc: one sentence on how the energy moves across the record. " \
    "texture: one sentence on the sonic palette. " \
    "seasons: any of spring, summer, autumn, winter that genuinely fit, else empty. " \
    "prose: 4-6 sentences painting specific listening scenarios, no generic filler."
  ).freeze

  class Schema < OpenAI::BaseModel
    required :time_of_day, OpenAI::ArrayOf[OpenAI::EnumOf["morning", "midday", "afternoon", "evening", "late night"]]
    required :activities, OpenAI::ArrayOf[String]
    required :energy_arc, String
    required :texture, String
    required :seasons, OpenAI::ArrayOf[OpenAI::EnumOf["spring", "summer", "autumn", "winter"]]
    required :prose, String
  end

  def initialize(client: default_client)
    @client = client
  end

  def generate(album)
    response = @client.responses.create(
      model: MODEL,
      input: [
        { role: :system, content: SYSTEM_PROMPT },
        { role: :user, content: "Album: #{album_description(album)}" }
      ],
      text: Schema,
      max_output_tokens: MAX_OUTPUT_TOKENS
    )

    response.output
      .select { |item| item.type == :message }
      .flat_map(&:content)
      .map(&:parsed)
      .compact
      .first
  rescue StandardError => e
    Rails.logger.warn("VibeCardGenerator failed for album #{album.id}: #{e.message}")
    nil
  end

  private

  def default_client
    OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
  end

  def album_description(album)
    parts = [album.title]
    parts << "by #{album.artists.join(", ")}" if album.artists.present?
    parts << "(#{album.year})" if album.year.present?
    parts << "genres: #{album.genres.join(", ")}" if album.genres.present?
    parts << "styles: #{album.styles.join(", ")}" if album.styles.present?
    parts.join(" ")
  end
end
