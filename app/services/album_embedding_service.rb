class AlbumEmbeddingService
  MODEL = "text-embedding-3-small"
  FACET_KEYS = %i[sonic emotional situational era].freeze

  def initialize(client: OpenAI::Client.new)
    @client = client
  end

  def embed(album, mood_vector, vibe_card)
    era = era_text(album)
    texts = [
      sonic_text(album).presence || era,
      emotional_text(vibe_card, mood_vector).presence || era,
      situational_text(vibe_card).presence || era,
      era
    ]

    response = @client.embeddings.create(model: MODEL, input: texts)
    FACET_KEYS.zip(response.data.map(&:embedding)).to_h
  end

  private

  def era_text(album)
    artist_text = album.artists.present? ? album.artists.join(", ") : "Unknown Artist"
    year_text = album.year.present? ? " (#{album.year})" : ""
    "Album: #{album.title} by #{artist_text}#{year_text}. #{sonic_text(album)}"
  end

  def sonic_text(album)
    "Sonic traits: #{sonic_traits_clause(album)}."
  end

  def sonic_traits_clause(album)
    clauses = []
    clauses << "genres include #{album.genres.join(", ")}" if album.genres.present?
    clauses << "styles include #{album.styles.join(", ")}" if album.styles.present?
    clauses.present? ? clauses.join("; ") : "genre and style details are limited in metadata"
  end

  def emotional_text(vibe_card, mood_vector)
    parts = []
    parts << "Energy: #{vibe_card.energy_arc}." if vibe_card.energy_arc.present?
    parts << "Texture: #{vibe_card.texture}." if vibe_card.texture.present?
    descriptor = MoodDescriptor.render(mood_vector)
    parts << "Audio-grounded mood: #{descriptor}." if descriptor.present?
    parts.join(" ")
  end

  def situational_text(vibe_card)
    parts = []
    parts << "Best times of day: #{vibe_card.time_of_day.join(", ")}." if vibe_card.time_of_day.present?
    parts << "Great while #{vibe_card.activities.join(", ")}." if vibe_card.activities.present?
    parts << "Seasons that fit: #{vibe_card.seasons.join(", ")}." if vibe_card.seasons.present?
    parts << vibe_card.prose if vibe_card.prose.present?
    parts.join(" ")
  end
end
