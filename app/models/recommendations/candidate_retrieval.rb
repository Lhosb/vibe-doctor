module Recommendations
  class CandidateRetrieval
    FACET_WEIGHTS = { sonic: 0.30, situational: 0.25, emotional: 0.15, era: 0.10 }.freeze
    # Fixture dispersion-matched weight is 0.192345; keeping 0.20 leaves a measured +3.98% mean residual.
    # No-clamp emomusic extremes permit term 1.190238, so the true maximum contribution is 0.238048.
    # These anchors are pinned by G15 in spec/models/mood_vectors/mood_distance_spec.rb.
    MOOD_VECTOR_WEIGHT = 0.20
    MAX_FACET_DISTANCE = 1.0
    PER_FACET_POOL_SIZE = 100

    Candidate = Struct.new(:album, :blended_score, keyword_init: true)

    def initialize(understanding, limit: 40, album_ids: nil)
      @understanding = understanding
      @limit = limit
      @album_ids = album_ids
      reset_head_instrumentation!
    end

    def call
      reset_head_instrumentation!
      maps = facet_distance_maps
      candidate_ids = maps.values.flat_map(&:keys).uniq
      return [] if candidate_ids.empty?

      albums = Album.where(id: candidate_ids).includes(:mood_vector).index_by(&:id)

      candidates = candidate_ids.map do |id|
        Candidate.new(album: albums.fetch(id), blended_score: blended_score(id, maps, albums.fetch(id)))
      end
      head_shares

      candidates
        .sort_by(&:blended_score)
        .first(@limit)
    end

    def head_shares
      raise "no candidates were scored" if @scored_count.zero?

      @head_shares ||= {
        "shares" => normalized_head_shares,
        "max_term" => @max_term,
        "scored_count" => @scored_count
      }
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
      mood_breakdown = MoodVectors::MoodDistance.breakdown(
        album_mood: album.mood_vector,
        query_mood: @understanding.mood_vector
      )
      record_head_instrumentation!(mood_breakdown)

      facet_distance + (MOOD_VECTOR_WEIGHT * mood_breakdown.term)
    end

    def reset_head_instrumentation!
      @head_totals = MoodVector::MOOD_HEADS.to_h { |head| [ head, 0.0 ] }
      @max_term = 0.0
      @scored_count = 0
      @head_shares = nil
    end

    def record_head_instrumentation!(breakdown)
      MoodVector::MOOD_HEADS.each do |head|
        @head_totals[head] += breakdown.per_head.fetch(head)
      end
      @max_term = [ @max_term, breakdown.term ].max
      @scored_count += 1
    end

    def normalized_head_shares
      total = @head_totals.values.sum

      MoodVector::MOOD_HEADS.to_h do |head|
        [ head.to_s, total.zero? ? 0.0 : @head_totals.fetch(head) / total ]
      end
    end
  end
end
