class QueryUnderstandingCache < ApplicationRecord
  TTL = 24.hours

  validates :query_digest, uniqueness: true

  def self.fetch(query_text, client: QueryUnderstandingClient.new)
    digest = digest_for(query_text)
    cached = find_by(query_digest: digest)
    return cached if cached && cached.expires_at.future?

    result = client.understand(query_text)
    row = cached || new(query_digest: digest)
    row.update!(
      query_text: query_text,
      valence: result.mood_vector.valence,
      arousal: result.mood_vector.arousal,
      danceability: result.mood_vector.danceability,
      mood_acoustic: result.mood_vector.mood_acoustic,
      mood_relaxed: result.mood_vector.mood_relaxed,
      mood_happy: result.mood_vector.mood_happy,
      genre: result.genre,
      keywords: result.keywords,
      embedding: result.embedding,
      expires_at: TTL.from_now
    )
    row
  end

  def self.digest_for(query_text)
    Digest::SHA256.hexdigest(query_text.strip.downcase)
  end

  def mood_vector
    MoodVector.new(
      valence: valence, arousal: arousal, danceability: danceability,
      mood_acoustic: mood_acoustic, mood_relaxed: mood_relaxed, mood_happy: mood_happy,
      mood_source: "llm_only"
    )
  end
end
