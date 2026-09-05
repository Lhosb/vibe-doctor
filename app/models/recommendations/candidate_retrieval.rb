module Recommendations
  class CandidateRetrieval
    FACET_WEIGHTS = { sonic: 0.30, situational: 0.25, emotional: 0.15, era: 0.10 }.freeze
    # Fixture dispersion-matched weight is 0.192345; keeping 0.20 leaves a measured +3.98% mean residual.
    # No-clamp emomusic extremes permit term 1.190238, so the true maximum contribution is 0.238048.
    MOOD_VECTOR_WEIGHT = 0.20
    MAX_FACET_DISTANCE = 1.0
    PER_FACET_POOL_SIZE = 100

    Candidate = Struct.new(:album, :blended_score, keyword_init: true)

    def initialize(understanding, limit: 40, album_ids: nil)
      @understanding = understanding
      @limit = limit
      @album_ids = album_ids
    end

    def call
      maps = facet_distance_maps
      candidate_ids = maps.values.flat_map(&:keys).uniq
      return [] if candidate_ids.empty?

      albums = Album.where(id: candidate_ids).includes(:mood_vector).index_by(&:id)

      candidate_ids
        .map { |id| Candidate.new(album: albums.fetch(id), blended_score: blended_score(id, maps, albums.fetch(id))) }
        .sort_by(&:blended_score)
        .first(@limit)
    end

    private

    def facet_distance_maps
      FACET_WEIGHTS.each_key.each_with_object({}) do |facet, memo|
        relation = Embedding.nearest_neighbors(facet, @understanding.embedding, distance: "cosine").limit(PER_FACET_POOL_SIZE)
        relation = relation.where(album_id: @album_ids) unless @album_ids.nil?
        memo[facet] = relation.each_with_object({}) { |embedding, m| m[embedding.album_id] = embedding.neighbor_distance }
      end
    end

    def blended_score(album_id, maps, album)
      facet_distance = FACET_WEIGHTS.sum { |facet, weight| weight * maps[facet].fetch(album_id, MAX_FACET_DISTANCE) }
      mood_distance = MoodVectors::MoodDistance.term(
        album_mood: album.mood_vector,
        query_mood: @understanding.mood_vector
      )
      facet_distance + (MOOD_VECTOR_WEIGHT * mood_distance)
    end
  end
end
